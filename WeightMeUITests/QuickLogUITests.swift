import XCTest

/// The front-page log card on demo data (no HealthKit needed).
final class QuickLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testDragRulerAndSave() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        let field = app.textFields["quickLogField"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        let start = Double(field.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(start, 100, "Card should start at the latest weight")
        snapshot(app, "40-quick-log")

        // Drag the ruler left: the number goes up.
        let ruler = app.otherElements["Weight ruler"]
        XCTAssertTrue(ruler.exists)
        let from = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let to = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        let dragged = Double(field.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(dragged, start, "Dragging left should increase the weight")
        snapshot(app, "41-quick-log-dragged")

        // Adjustable from VoiceOver too.
        ruler.swipeUp()

        app.buttons["quickLogSave"].tap()
        let saveAnyway = app.buttons["Save Anyway"]
        if saveAnyway.waitForExistence(timeout: 1) { saveAnyway.tap() }
        XCTAssertTrue(app.buttons["Saved to Apple Health"].waitForExistence(timeout: 4))
        let saved = field.value as? String ?? ""
        XCTAssertTrue(app.staticTexts[saved].waitForExistence(timeout: 3), "Latest should show the logged weight")
        snapshot(app, "42-quick-log-saved")

        // Typing works too.
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        field.typeText("180.4")
        snapshot(app, "43-quick-log-typing")
        XCTAssertTrue(app.buttons["quickLogSave"].isEnabled)
    }
}
