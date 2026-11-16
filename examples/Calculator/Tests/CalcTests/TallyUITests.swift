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
        while !last.exists && swipes < 8 {
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

    @MainActor func testPadCoordinateTaps() throws {
        let app = XCUIApplication()
        app.launch()
        let pad = app.otherElements["pad"]
        for _ in 0..<10 where !pad.exists { app.swipeUp(velocity: .slow) }  // below the first screen (a container is never "hittable")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["side"].label, "Tap: right")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["side"].label, "Tap: left")
    }

    @MainActor func testPadPinchAndRotate() throws {
        let app = XCUIApplication()
        app.launch()
        let pad = app.otherElements["pad"]
        for _ in 0..<10 where !pad.exists { app.swipeUp(velocity: .slow) }  // below the first screen (a container is never "hittable")
        pad.pinch(withScale: 2, velocity: 1)
        pad.rotate(.pi / 2, withVelocity: 1)
        let label = app.staticTexts["zoom"].label  // "Zoom: 2.0, angle: 90"
        print("pad after pinch and rotate: \(label)")
        let numbers = label.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
        XCTAssertEqual(numbers.count, 2, label)
        XCTAssertGreaterThan(numbers.first ?? 0, 1.3, label)
        XCTAssertGreaterThan(abs(numbers.last ?? 0), 30, label)
    }

    /// terminate() takes the app off screen (Peek itself keeps running); launch() brings it back.
    @MainActor func testTerminateAndLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Add"].tap()
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        XCTAssertFalse(app.buttons["Add"].exists)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(app.staticTexts["count"].label, "Count: 0")
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

/// Another app: Peek keeps running in the background while Settings is in front.
final class OtherAppUITests: XCTestCase {
    @MainActor func testSettingsGeneral() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        let general = settings.staticTexts["일반"].exists ? settings.staticTexts["일반"] : settings.staticTexts["General"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.tap()
        XCTAssertTrue(settings.navigationBars.firstMatch.waitForExistence(timeout: 5))
        print("Settings now shows: \(settings.navigationBars.firstMatch.identifier)")
        settings.navigationBars.buttons.firstMatch.tap()  // back
        let app = XCUIApplication()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// launch() brings another app to the front (peek cannot start it afresh); terminate() quits it.
    @MainActor func testSettingsLaunchAndTerminate() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        settings.terminate()
        XCTAssertTrue(settings.wait(for: .notRunning, timeout: 10))
        let app = XCUIApplication()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))
    }
}

/// The device itself: home button, screenshots, rotation.
final class DeviceUITests: XCTestCase {
    @MainActor func testHomeButtonAndBack() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))
    }

    @MainActor func testScreenshot() throws {
        let app = XCUIApplication()
        app.launch()
        let shot = app.screenshot()
        print("screenshot: \(shot.image.size) at scale \(shot.image.scale), \(shot.pngRepresentation.count) bytes")
        XCTAssertGreaterThan(shot.pngRepresentation.count, 10_000)
        let attachment = XCTAttachment(screenshot: shot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testRotation() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let window = app.windows.firstMatch
        let rotated = expectation(for: NSPredicate { _, _ in window.frame.width > window.frame.height }, evaluatedWith: nil)
        wait(for: [rotated], timeout: 5)
        XCTAssertTrue(app.buttons["Add"].isHittable)
    }
}
