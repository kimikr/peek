import XCTest

/// Plain XCUITests, as Xcode would run them; `peek test` runs them on the phone.
final class TallyUITests: XCTestCase {
    @MainActor func testAddAndReset() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Add"].tap()
        app.buttons["Add"].tap()
        XCTAssertEqual(app.staticTexts["count"].label, "Count: 2")
        app.buttons["Reset"].tap()
        XCTAssertEqual(app.staticTexts["count"].label, "Count: 0")
    }

    @MainActor func testTyping() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["name"]
        field.tap()
        field.typeText("Peek")
        XCTAssertEqual(app.staticTexts["greeting"].label, "Hello, Peek!")
    }
}
