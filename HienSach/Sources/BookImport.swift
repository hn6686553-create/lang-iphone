import Foundation
import CryptoKit
import ZIPFoundation
import PDFKit
import ImageIO
import UIKit

enum BookImport {
    static let maxBytes = 200 * 1024 * 1024
    private static let fm = FileManager.default

    static func prepare(_ source: URL, fileName: String, booksRoot: URL) throws -> Book {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try fm.createDirectory(at: booksRoot, withIntermediateDirectories: true)
        let staging = booksRoot.appendingPathComponent(".inbox-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        // Copy while the provider grants read access; parse a stable private copy.
        let input = staging.appendingPathComponent("incoming")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard size.isRegularFile == true, (size.fileSize ?? 0) <= maxBytes else {
                    throw ReaderFailure("Hãy chọn một tệp sách tối đa 200 MB.")
                }
                try fm.copyItem(at: url, to: input)
            } catch { copyError = error }
        }
        if let error = copyError ?? coordinationError { throw error }
        let stream = try FileHandle(forReadingFrom: input)
        defer { try? stream.close() }
        var hash = SHA256()
        var head = Data()
        var total = 0
        while let block = try stream.read(upToCount: 262_144), !block.isEmpty {
            try Task.checkCancellation()
            total += block.count
            guard total <= maxBytes else { throw ReaderFailure("Tệp vượt quá 200 MB.") }
            if head.isEmpty { head = Data(block.prefix(1024)) }
            hash.update(data: block)
        }
        guard total > 0 else { throw ReaderFailure("Tệp sách đang trống.") }
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let title = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let book: Book
        if head.starts(with: [0x50,0x4b]) {
            book = try epub(input, staging, id, title)
            try fm.removeItem(at: input)
        } else if head.range(of: Data("%PDF-".utf8)) != nil {
            let pdf = staging.appendingPathComponent("document.pdf")
            try fm.moveItem(at: input, to: pdf)
            book = try pdfBook(pdf, staging, id, title)
        } else if (fileName as NSString).pathExtension.lowercased() == "txt" {
            book = try textBook(input, staging, id, title)
            try fm.removeItem(at: input)
        } else {
            throw ReaderFailure("Tệp nhận được chưa phải EPUB, PDF hoặc TXT. Với sách online, hãy dùng đường dẫn tải tệp trực tiếp.")
        }
        let destination = booksRoot.appendingPathComponent(id, isDirectory: true)
        if !fm.fileExists(atPath: destination.path) { try fm.moveItem(at: staging, to: destination) }
        return book
    }

    private static func extract(_ archive: Archive, into root: URL) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var total: UInt64 = 0
        var entries = 0
        var seen = Set<String>()
        for entry in archive {
            try Task.checkCancellation()
            entries += 1
            let name = entry.path
            let parts = name.split(separator: "/")
            guard entries <= 12_000, !name.hasPrefix("/"), !name.contains("\\"),
                  !name.contains("\0"), !parts.contains(".."), !parts.contains("."),
                  !parts.isEmpty, entry.type != .symlink else { throw ReaderFailure("EPUB chứa đường dẫn không hợp lệ.") }
            guard entry.uncompressedSize <= 80 * 1024 * 1024 else { throw ReaderFailure("Một thành phần EPUB quá lớn.") }
            total += entry.uncompressedSize
            guard total <= 450 * 1024 * 1024 else { throw ReaderFailure("EPUB vượt giới hạn giải nén 450 MB.") }
            let target = root.appendingPathComponent(name).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ReaderFailure("Đường dẫn EPUB không hợp lệ.") }
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            guard seen.insert(target.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw ReaderFailure("EPUB chứa hai tệp trùng tên.")
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw ReaderFailure("Không thể lưu nội dung sách.") }
            let file = try FileHandle(forWritingTo: target)
            defer { try? file.close() }
            var produced: UInt64 = 0
            let crc = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                produced += UInt64(chunk.count)
                guard produced <= entry.uncompressedSize else { throw ReaderFailure("Dữ liệu nén không hợp lệ.") }
                try file.write(contentsOf: chunk)
            }
            guard produced == entry.uncompressedSize, crc == entry.checksum else { throw ReaderFailure("Tệp EPUB bị hỏng hoặc tải chưa đủ.") }
        }
    }

    private static func epub(_ input: URL, _ folder: URL, _ id: String, _ fallback: String) throws -> Book {
        let root = folder.appendingPathComponent("content", isDirectory: true)
        let archive = try Archive(url: input, accessMode: .read)
        try extract(archive, into: root)
        let container = root.appendingPathComponent("META-INF/container.xml")
        guard fm.fileExists(atPath: container.path),
              let opf = try BookXML.read(container).descendants("rootfile").compactMap({ $0.attrs["full-path"] }).first,
              let package = BookPath(opf, relativeTo: root.appendingPathComponent("index"), root: root) else {
            throw ReaderFailure("Gói ZIP thiếu mục lục chuẩn của EPUB.")
        }
        let encryption = root.appendingPathComponent("META-INF/encryption.xml")
        if fm.fileExists(atPath: encryption.path) {
            let algorithms = try BookXML.read(encryption).descendants("encryptionmethod").compactMap { $0.attrs["Algorithm"] }
            guard !algorithms.isEmpty, algorithms.allSatisfy({ ["http://www.idpf.org/2008/embedding","http://ns.adobe.com/pdf/enc#RC"].contains($0) }) else {
                throw ReaderFailure("EPUB này có DRM. Hãy mở bằng ứng dụng của nơi phát hành.")
            }
        }
        let xml = try BookXML.read(package.file)
        let metadata = xml.descendants("metadata").first
        let name = metadata?.descendants("title").first?.text.clean ?? ""
        let author = metadata?.descendants("creator").map { $0.text.clean }.filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
        var book = Book(id: id, title: name.isEmpty ? fallback : name, author: author, kind: .epub)
        var items: [String:BookNode] = [:]
        for item in xml.descendants("manifest").first?.children ?? [] {
            if let key = item.attrs["id"] { items[key] = item }
        }
        func link(_ node: BookNode?) -> BookPath? {
            guard let href = node?.attrs["href"] else { return nil }
            return BookPath(href, relativeTo: package.file, root: root)
        }
        let spine = xml.descendants("spine").first
        for ref in spine?.children ?? [] where ref.name == "itemref" && ref.attrs["linear"] != "no" {
            guard let item = items[ref.attrs["idref"] ?? ""], let path = link(item),
                  ["application/xhtml+xml","text/html"].contains(item.attrs["media-type"] ?? ""),
                  fm.fileExists(atPath: path.file.path) else { continue }
            book.chapters.append(Chapter(file: path.relative, title: "Phần \(book.chapters.count + 1)"))
        }
        guard !book.chapters.isEmpty else { throw ReaderFailure("EPUB không có chương văn bản đọc được.") }
        var chapterIndices: [String:Int] = [:]
        for (i,c) in book.chapters.enumerated() where chapterIndices[c.file] == nil { chapterIndices[c.file] = i }
        func add(_ label: String, _ href: String, _ base: URL) {
            guard !label.clean.isEmpty, let target = BookPath(href, relativeTo: base, root: root),
                  let index = chapterIndices[target.relative], book.contents.count < 3500 else { return }
            book.contents.append(.init(title: label.clean, spot: .init(unit: index, fragment: target.fragment)))
        }
        let navItem = items.values.first { ($0.attrs["properties"] ?? "").split(separator: " ").contains("nav") }
        if let nav = link(navItem), let doc = try? BookXML.read(nav.file) {
            let section = doc.descendants("nav").first { ($0.attrs["epub:type"] ?? $0.attrs["type"] ?? "").split(separator: " ").contains("toc") } ?? doc.descendants("nav").first
            for a in section?.descendants("a") ?? [] { if let h = a.attrs["href"] { add(a.text, h, nav.file) } }
        }
        if book.contents.isEmpty {
            let ncxItem = items[spine?.attrs["toc"] ?? ""] ?? items.values.first { $0.attrs["media-type"] == "application/x-dtbncx+xml" }
            if let ncx = link(ncxItem), let doc = try? BookXML.read(ncx.file) {
                for point in doc.descendants("navpoint") {
                    if let label = point.children.first(where: { $0.name=="navlabel" })?.text,
                       let h = point.children.first(where: { $0.name=="content" })?.attrs["src"] { add(label,h,ncx.file) }
                }
            }
        }
        var named = Set<Int>()
        for toc in book.contents where named.insert(toc.spot.unit).inserted { book.chapters[toc.spot.unit].title = toc.title }
        if book.contents.isEmpty {
            book.contents = book.chapters.enumerated().map { .init(title: $0.element.title, spot: .init(unit:$0.offset)) }
        }
        let coverID = metadata?.descendants("meta").first { $0.attrs["name"] == "cover" }?.attrs["content"]
        let coverItem = items.values.first { ($0.attrs["properties"] ?? "").split(separator:" ").contains("cover-image") } ?? items[coverID ?? ""]
        if let url = link(coverItem)?.file, let image = CGImageSourceCreateWithURL(url as CFURL, nil),
           let thumb = CGImageSourceCreateThumbnailAtIndex(image, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:600,
            kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) {
            book.cover = try saveCover(UIImage(cgImage: thumb), folder)
        }
        return book
    }

    private static func saveCover(_ image: UIImage, _ folder: URL) throws -> String? {
        guard let bytes = image.jpegData(compressionQuality: 0.85) else { return nil }
        try bytes.write(to: folder.appendingPathComponent("cover.jpg"), options:.atomic)
        return "cover.jpg"
    }

    private static func pdfBook(_ file: URL, _ folder: URL, _ id: String, _ fallback: String) throws -> Book {
        guard let doc = PDFDocument(url: file) else { throw ReaderFailure("Không đọc được tệp PDF.") }
        guard !doc.isLocked else { throw ReaderFailure("PDF cần mật khẩu. Hãy nhập một bản đã được mở khóa.") }
        guard doc.pageCount > 0, let first = doc.page(at: 0) else { throw ReaderFailure("PDF không có trang.") }
        let name = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.clean ?? ""
        let author = (doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)?.clean ?? ""
        var book = Book(id:id,title:name.isEmpty ? fallback : name,author:author,kind:.pdf)
        book.pdfPages = doc.pageCount
        book.cover = try saveCover(first.thumbnail(of: CGSize(width: 360,height: 530),for:.cropBox),folder)
        func walk(_ node: PDFOutline, _ depth: Int) {
            guard depth < 24, book.contents.count < 1000 else { return }
            for n in 0..<min(node.numberOfChildren,1000) {
                guard let child = node.child(at:n) else { continue }
                if let page = (child.destination ?? (child.action as? PDFActionGoTo)?.destination)?.page,
                   let label = child.label, !label.clean.isEmpty {
                    let i = doc.index(for:page)
                    if i < doc.pageCount { book.contents.append(.init(title:label,spot:.init(unit:i))) }
                }
                walk(child,depth+1)
            }
        }
        if let outline = doc.outlineRoot { walk(outline,0) }
        return book
    }

    private static func textBook(_ file: URL, _ folder: URL, _ id: String, _ title: String) throws -> Book {
        let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size <= 24_000_000 else { throw ReaderFailure("Tệp TXT vượt quá 24 MB. Hãy chia thành các tập nhỏ hơn.") }
        let bytes = try Data(contentsOf:file)
        let utf16 = bytes.starts(with:[0xff,0xfe]) || bytes.starts(with:[0xfe,0xff])
        guard let source = String(data:bytes,encoding:utf16 ? .utf16 : .utf8), !source.clean.isEmpty else {
            throw ReaderFailure("Hãy lưu TXT ở mã hóa UTF-8 hoặc UTF-16.")
        }
        let root = folder.appendingPathComponent("content")
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        var book = Book(id:id,title:title,author:"",kind:.txt)
        var paragraphs = [String]()
        var length = 0
        func flush() throws {
            guard !paragraphs.isEmpty else { return }
            let n = book.chapters.count + 1, path = "part-\(n).html"
            let label = n == 1 ? title : "Phần \(n)"
            let body = paragraphs.map { "<p>" + $0.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;") + "</p>" }.joined()
            try ("<!doctype html><html><head><meta charset='utf-8'></head><body>" + body + "</body></html>").write(to:root.appendingPathComponent(path),atomically:true,encoding:.utf8)
            book.chapters.append(.init(file:path,title:label))
            book.contents.append(.init(title:label,spot:.init(unit:n-1)))
            paragraphs.removeAll(keepingCapacity:true); length=0
        }
        for line in source.split(whereSeparator: \.isNewline) {
            var rest = line[...]
            while !rest.isEmpty {
                let cut = rest.index(rest.startIndex,offsetBy:8000,limitedBy:rest.endIndex) ?? rest.endIndex
                let piece = String(rest[..<cut])
                paragraphs.append(piece);length += piece.utf8.count
                if length >= 24_000 { try flush() }
                rest = rest[cut...]
            }
        }
        try flush()
        return book
    }
}
extension String { var clean: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
