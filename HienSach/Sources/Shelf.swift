import SwiftUI
import UniformTypeIdentifiers

struct OpenBook: Identifiable {
    let id: String
    let spot: ReadingSpot
}
struct ShelfNotice: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class Shelf: ObservableObject {
    @Published private(set) var books: [Book]
    @Published var options: ReaderOptions { didSet { scheduleSave() } }
    @Published var reading: OpenBook?
    @Published var notice: ShelfNotice?
    @Published private(set) var busy = false
    let root: URL
    var booksRoot: URL { root.appendingPathComponent("Books", isDirectory: true) }
    private var seeded: Bool
    private var bootstrapped = false
    private var queue: [(URL, String, Bool, Bool)] = []
    private var saveTask: Task<Void, Never>?
    private let fm = FileManager.default
    private var preserveIndex = false

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HienSach", isDirectory: true)
        self.root = base
        let index = base.appendingPathComponent("Index.json")
        var data = LibraryIndex()
        var readError: Error?
        if FileManager.default.fileExists(atPath: index.path) {
            do { data = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf:index)) }
            catch { readError = error }
        }
        books = data.books
        options = data.options
        seeded = data.seeded
        if readError != nil {
            do {
                try FileManager.default.copyItem(at:index, to:base.appendingPathComponent("Index-\(UUID().uuidString).backup"))
            } catch { preserveIndex = true }
            notice = ShelfNotice(text:"Chưa đọc được danh sách sách đã lưu. Các tệp sách vẫn còn trên máy.")
        }
    }
    func folder(_ id: String) -> URL { booksRoot.appendingPathComponent(id, isDirectory:true) }
    func book(_ id: String) -> Book? { books.first { $0.id == id } }
    func bootstrap() {
        guard !bootstrapped else { return }; bootstrapped = true
        guard !seeded, let dir = Bundle.main.url(forResource:"Seeds",withExtension:nil),
              let files = try? fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil) else { return }
        let seeds = files.filter { ["epub","pdf"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in seeds { queue.append((url,url.lastPathComponent,false,false)) }
        if !seeds.isEmpty { drain(seeding:true) }
    }
    func importFiles(_ urls:[URL], open:Bool = true) {
        for (i,url) in urls.enumerated() { queue.append((url,url.lastPathComponent,open && i == urls.count-1,false)) }
        drain()
    }
    func downloaded(_ url:URL,name:String) {
        queue.append((url,name,true,true)); drain()
    }
    private func drain(seeding:Bool = false) {
        guard !busy else { return }
        busy = true
        Task {
            var anySeedFailed = false
            while !queue.isEmpty {
                let (url,name,open,temporary) = queue.removeFirst()
                let dest = booksRoot
                do {
                    let incoming = try await Task.detached(priority:.userInitiated) { try BookImport.prepare(url,fileName:name,booksRoot:dest) }.value
                    if book(incoming.id) == nil { books.append(incoming); flush() }
                    if open { self.open(incoming.id) }
                } catch {
                    if seeding && !open && !temporary { anySeedFailed = true }
                    notice = ShelfNotice(text:"\(name)\n\(error.localizedDescription)")
                }
                if temporary { try? fm.removeItem(at:url) }
            }
            if seeding && !anySeedFailed { seeded = true; flush() }
            busy = false
        }
    }
    func open(_ id:String, at requested:ReadingSpot? = nil) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        let spot = requested ?? books[i].spot
        books[i].opened = Date()
        books[i].spot = spot
        reading = OpenBook(id:id,spot:spot); flush()
    }
    func record(_ id:String,spot:ReadingSpot) {
        guard let i = books.firstIndex(where: { $0.id == id }), books[i].spot != spot else { return }
        books[i].spot = spot; scheduleSave()
    }
    func toggleRibbon(_ id:String,spot:ReadingSpot) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        if let j = books[i].ribbons.firstIndex(where:{ Self.matches($0.spot,spot) }) { books[i].ribbons.remove(at:j) }
        else { let label = books[i].label(at:spot); books[i].ribbons.append(Ribbon(id:UUID(),label:label,spot:spot,date:Date())) }
        flush()
    }
    static func matches(_ a:ReadingSpot,_ b:ReadingSpot) -> Bool {
        a.unit == b.unit && (a.paragraph != nil && a.paragraph == b.paragraph && abs(a.fraction-b.fraction) < 0.04 || abs(a.fraction-b.fraction) < 0.003)
    }
    func removeRibbon(_ id:String, _ ribbon:UUID) {
        if let i=books.firstIndex(where:{ $0.id==id }) { books[i].ribbons.removeAll { $0.id == ribbon }; flush() }
    }
    func finish(_ id:String, _ finished:Bool) {
        if let i=books.firstIndex(where:{ $0.id==id }) { books[i].finished=finished; flush() }
    }
    func remove(_ id:String) {
        guard let i=books.firstIndex(where:{ $0.id==id }) else { return }
        let retained=books.remove(at:i)
        if saveNow() { try? fm.removeItem(at:folder(id)) } else { books.insert(retained,at:i) }
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(nanoseconds:350_000_000); if !Task.isCancelled { self.flush() } }
    }
    func flush() { saveTask?.cancel(); saveTask=nil; _ = saveNow() }
    private func saveNow() -> Bool {
        guard !preserveIndex else { return false }
        do {
            try fm.createDirectory(at:root,withIntermediateDirectories:true)
            try JSONEncoder().encode(LibraryIndex(books:books,seeded:seeded,options:options)).write(to:root.appendingPathComponent("Index.json"),options:.atomic)
            return true
        } catch { notice=ShelfNotice(text:"iPhone chưa lưu được thay đổi. \(error.localizedDescription)"); return false }
    }
}
