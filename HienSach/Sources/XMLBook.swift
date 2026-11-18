import Foundation

final class BookNode {
    let name: String
    let attrs: [String: String]
    var children: [BookNode] = []
    var text = ""
    init(_ name: String, _ attrs: [String: String]) {
        self.name = name.components(separatedBy: ":").last?.lowercased() ?? name
        self.attrs = attrs
    }
    func descendants(_ name: String) -> [BookNode] {
        children.flatMap { child in (child.name == name ? [child] : []) + child.descendants(name) }
    }
}

final class BookXML: NSObject, XMLParserDelegate {
    private var stack: [BookNode] = []
    private var count = 0
    private var root: BookNode?

    static func read(_ url: URL) throws -> BookNode {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 6_000_000 else { throw ReaderFailure("Mục lục hoặc thông tin EPUB quá lớn.") }
        let data = try Data(contentsOf: url)
        let reader = BookXML()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let root = reader.root else { throw ReaderFailure("Không đọc được cấu trúc EPUB.") }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        count += 1
        guard stack.count < 120, count < 100_000 else { parser.abortParsing(); return }
        let node = BookNode(elementName, attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let node = stack.last, node.text.utf8.count < 12_000 { node.text += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let node = stack.popLast() else { return }
        if let parent = stack.last, parent.text.utf8.count < 12_000 { parent.text += node.text }
    }
}

struct BookPath {
    let file: URL
    let relative: String
    let fragment: String?

    init?(_ href: String, relativeTo baseFile: URL, root: URL) {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let encoded = (parts.first.map(String.init) ?? "").components(separatedBy: "?")[0]
        guard let path = encoded.removingPercentEncoding,
              !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              URLComponents(string: path)?.scheme == nil else { return nil }
        let target = (path.isEmpty ? baseFile : baseFile.deletingLastPathComponent().appendingPathComponent(path)).standardizedFileURL
        let prefix = root.standardizedFileURL.path + "/"
        guard target.path.hasPrefix(prefix) else { return nil }
        file = target
        relative = String(target.path.dropFirst(prefix.count))
        fragment = parts.count == 2 ? String(parts[1]).removingPercentEncoding : nil
    }
}
