import XCTest
final class ReadingUITests:XCTestCase{
    override func setUp(){super.setUp();continueAfterFailure=false}
    func testReadEPUBBookmarkSettingsAndRestore(){
        let app=XCUIApplication();app.launch()
        let cover=app.buttons["cover-Bên ô cửa"];XCTAssertTrue(cover.waitForExistence(timeout:25));cover.tap()
        let toc=app.buttons["contents"];XCTAssertTrue(toc.waitForExistence(timeout:7));toc.tap()
        let chapter=app.buttons["Một chỗ ngồi"];XCTAssertTrue(chapter.waitForExistence(timeout:6));chapter.tap()
        let name=app.staticTexts["chapterName"]
        let predicate=NSPredicate(format:"label == %@", "Một chỗ ngồi")
        expectation(for:predicate,evaluatedWith:name);waitForExpectations(timeout:12)
        let state=app.staticTexts["pageState"], previous=state.label
        app.buttons["next"].tap()
        expectation(for:NSPredicate(format:"label != %@",previous),evaluatedWith:state);waitForExpectations(timeout:8)
        let loc=state.label
        app.buttons["ribbon"].tap()
        app.buttons["appearance"].tap()
        let color=app.buttons["Xanh dịu"];XCTAssertTrue(color.waitForExistence(timeout:6));color.tap()
        app.buttons["doneSettings"].tap()
        app.buttons["closeReader"].tap()
        app.tabBars.buttons["Dấu trang"].tap()
        let mark=app.buttons.matching(NSPredicate(format:"label CONTAINS %@ OR label CONTAINS %@", "Một chỗ ngồi","Buổi chiều trở lại")).first
        XCTAssertTrue(mark.waitForExistence(timeout:8));mark.tap()
        expectation(for:NSPredicate(format:"label == %@",loc),evaluatedWith:app.staticTexts["pageState"]);waitForExpectations(timeout:10)
    }
    func testPDFNavigation(){
        let app=XCUIApplication();app.launch()
        let c=app.buttons["cover-Ga nhỏ cuối chiều"];XCTAssertTrue(c.waitForExistence(timeout:20));c.tap()
        let state=app.staticTexts["pageState"]
        let begin=NSPredicate(format:"label == %@", "Trang 1 / 3")
        expectation(for:begin,evaluatedWith:state);waitForExpectations(timeout:8)
        app.buttons["next"].tap()
        expectation(for:NSPredicate(format:"label == %@", "Trang 2 / 3"),evaluatedWith:state);waitForExpectations(timeout:8)
        app.buttons["closeReader"].tap()
    }
}
