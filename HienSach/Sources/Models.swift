import Foundation
import SwiftUI

struct ReaderFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum BookKind: String, Codable { case epub = "EPUB", pdf = "PDF", txt = "TXT" }

struct ReadingSpot: Codable, Equatable, Hashable {
    var unit = 0
    var fraction = 0.0
    var paragraph: Int?
    var fragment: String?
    var findText: String?
}

struct Chapter: Codable, Equatable {
    let file: String
    var title: String
}

struct ContentsEntry: Codable, Hashable {
    let title: String
    let spot: ReadingSpot
}

struct Ribbon: Codable, Identifiable, Equatable {
    let id: UUID
    let label: String
    let spot: ReadingSpot
    let date: Date
}

struct Book: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var author: String
    let kind: BookKind
    var chapters: [Chapter] = []
    var contents: [ContentsEntry] = []
    var pdfPages = 0
    var cover: String?
    var added = Date()
    var opened: Date?
    var spot = ReadingSpot()
    var ribbons: [Ribbon] = []
    var finished = false

    var units: Int { max(1, kind == .pdf ? pdfPages : chapters.count) }
    var progress: Double {
        if finished { return 1 }
        guard opened != nil else { return 0 }
        if kind == .pdf { return Double(spot.unit + 1) / Double(units) }
        return min(1, max(0, (Double(spot.unit) + spot.fraction) / Double(units)))
    }
    func label(at location: ReadingSpot) -> String {
        if kind == .pdf { return "Trang \(location.unit + 1)" }
        return chapters.indices.contains(location.unit) ? chapters[location.unit].title : title
    }
}

enum Paper: String, Codable, CaseIterable, Identifiable {
    case ivory, white, sage, night
    var id: Self { self }
    var title: String { switch self { case .ivory: "Giấy ngà"; case .white: "Giấy trắng"; case .sage: "Xanh dịu"; case .night: "Đêm" } }
    var background: String { switch self { case .ivory: "#f5ead3"; case .white: "#fffdf8"; case .sage: "#dfe8d7"; case .night: "#201f1b" } }
    var ink: String { self == .night ? "#e6ddcd" : "#302a22" }
}
enum Typeface: String, Codable, CaseIterable, Identifiable {
    case book = "Có chân", clean = "Không chân", classic = "Cổ điển"
    var id: Self { self }
    var css: String { switch self { case .book: "Charter, Georgia, serif"; case .clean: "-apple-system, sans-serif"; case .classic: "'Palatino', Georgia, serif" } }
}
struct ReaderOptions: Codable, Equatable {
    var paper = Paper.ivory
    var typeface = Typeface.book
    var size = 20.0
    var leading = 1.65
    var margin = 22.0
    var curled = true
    var paged = true
}
extension Color {
    init(bookHex: String) {
        let n = UInt64(bookHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB, red: Double(n >> 16 & 255)/255, green: Double(n >> 8 & 255)/255, blue: Double(n & 255)/255)
    }
}

struct LibraryIndex: Codable {
    var books: [Book] = []
    var seeded = false
    var options = ReaderOptions()
}
