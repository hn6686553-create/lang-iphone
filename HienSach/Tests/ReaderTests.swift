import XCTest
@testable import HienSach

final class ReaderTests:XCTestCase{
    var root:URL!
    override func setUpWithError()throws{root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    override func tearDownWithError()throws{try FileManager.default.removeItem(at:root)}
    private func seed(_ name:String,_ ext:String)throws->URL{try XCTUnwrap(Bundle.main.url(forResource:name,withExtension:ext,subdirectory:"Seeds"))}
    func testEPUBSpineNavCoverAndStableIdentity()throws{
        let url=try seed("01-ben-o-cua","epub")
        let b=try BookImport.prepare(url,fileName:url.lastPathComponent,booksRoot:root)
        XCTAssertEqual(b.title,"Bên ô cửa");XCTAssertEqual(b.author,"Hiên Sách");XCTAssertEqual(b.chapters.count,3)
        XCTAssertEqual(b.contents[1].spot,ReadingSpot(unit:1,fragment:"head"));XCTAssertEqual(b.chapters[1].title,"Một chỗ ngồi")
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent(b.id).appendingPathComponent("cover.jpg").path))
        XCTAssertEqual(try BookImport.prepare(url,fileName:"another.epub",booksRoot:root).id,b.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[b.id])
    }
    func testPDFPageCountOutlineAndCover()throws{
        let p=try seed("03-ga-nho","pdf");let b=try BookImport.prepare(p,fileName:"ga.pdf",booksRoot:root)
        XCTAssertEqual(b.kind,.pdf);XCTAssertEqual(b.pdfPages,3);XCTAssertEqual(b.title,"Ga nhỏ cuối chiều");XCTAssertNotNil(b.cover)
        XCTAssertTrue(b.contents.contains{$0.title=="Sau hồi còi" && $0.spot.unit==2})
    }
    func testPlainTextIsEscapedAndPersists()throws{
        let p=root.appendingPathComponent("Nắng.txt");try "Ngày mưa\n<hello> & lá".write(to:p,atomically:true,encoding:.utf8)
        let b=try BookImport.prepare(p,fileName:p.lastPathComponent,booksRoot:root)
        let content=try String(contentsOf:root.appendingPathComponent(b.id+"/content/"+b.chapters[0].file),encoding:.utf8)
        XCTAssertEqual(b.title,"Nắng");XCTAssertTrue(content.contains("&lt;hello&gt; &amp; lá"))
    }
    func testInvalidDownloadsAndPathEscape()throws{
        let p=root.appendingPathComponent("download.html");try "<html>error</html>".write(to:p,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try BookImport.prepare(p,fileName:"index.epub",booksRoot:root))
        XCTAssertNil(BookPath("../%2e%2e/private",relativeTo:root.appendingPathComponent("OPS/book.opf"),root:root))
        XCTAssertNil(BookPath("https://example.org/book",relativeTo:p,root:root))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix(".inbox-")})
    }
    @MainActor func testBookmarksProgressAndAppearanceSurviveReopen()throws{
        let b=Book(id:"test",title:"Tủ",author:"",kind:.pdf,pdfPages:6)
        let data=try JSONEncoder().encode(LibraryIndex(books:[b],seeded:true));try data.write(to:root.appendingPathComponent("Index.json"))
        let s=Shelf(root:root);s.open("test");s.record("test",spot:.init(unit:3));s.toggleRibbon("test",spot:.init(unit:3));s.options.paper = .night;s.flush()
        let next=Shelf(root:root)
        XCTAssertEqual(next.book("test")?.spot.unit,3);XCTAssertEqual(next.book("test")?.ribbons.count,1);XCTAssertEqual(next.options.paper,.night)
    }
}
