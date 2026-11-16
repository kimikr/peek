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

    @MainActor func testGestures() throws {
        let app = XCUIApplication()
        app.launch()
        let toggle = app.switches["notify"]
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.sliders["level"].adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertNotEqual(app.staticTexts["levelText"].label, "Level 50")
        app.buttons["Add"].press(forDuration: 1)
        let last = app.staticTexts["Row 30"]
        var swipes = 0
        while !last.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(last.isHittable, "Row 30 not reached after \(swipes) swipes")
    }
}
