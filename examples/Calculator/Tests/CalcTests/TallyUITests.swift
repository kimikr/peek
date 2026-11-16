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

    @MainActor func testLaunchArgumentsAndEnvironment() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["START_COUNT": "5"]
        app.launch()
        XCTAssertEqual(app.staticTexts["mode"].label, "Mode: UI testing")
        XCTAssertEqual(app.staticTexts["count"].label, "Count: 5")
    }


    /// A system alert that appears every time: iOS asks before calling a tel: link.
    @MainActor func testCallConfirmationAlert() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Call support"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "no call confirmation")
        print("alert: \(alert.label) buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        let cancel = alert.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '취소'")).firstMatch
        XCTAssertTrue(cancel.exists)
        cancel.tap()
        XCTAssertTrue(app.buttons["Call support"].waitForExistence(timeout: 3))
    }
}
