import XCTest

/// The front-page log card on demo data (no HealthKit needed).
final class LatestWeightCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func value(_ field: XCUIElement) -> Double {
        Double(field.value as? String ?? "") ?? 0
    }

    @MainActor private func dragRulerUp(_ app: XCUIApplication) {
        let ruler = app.otherElements["Weight ruler"]
        XCTAssertTrue(ruler.exists)
        let from = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let to = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    @MainActor func testDragCancelSaveAndType() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        // At rest: the latest weight, no Save/Cancel.
        let field = app.textFields["quickLogField"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '7-day average'")).firstMatch.exists)
        let save = app.buttons["quickLogSave"]
        let cancel = app.buttons["quickLogCancel"]
        XCTAssertFalse(save.exists)
        XCTAssertFalse(cancel.exists)
        let start = value(field)
        XCTAssertGreaterThan(start, 100, "Card should show the latest weight")
        snapshot(app, "40-at-rest")

        // Drag left: the number goes up and Cancel/Save appear.
        dragRulerUp(app)
        XCTAssertGreaterThan(value(field), start, "Dragging left should increase the weight")
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["NEW WEIGHT"].exists)
        XCTAssertFalse(app.staticTexts["quickLogReplaces"].exists, "Demo's latest is hours old: adds, doesn't replace")
        XCTAssertFalse(app.buttons["Date and time"].exists, "No time picker on the main card")
        snapshot(app, "41-editing")

        // Cancel puts it back.
        cancel.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 2))
        XCTAssertEqual(value(field), start, accuracy: 0.001)

        // Drag and save: back at rest, showing the new reading as the latest.
        dragRulerUp(app)
        let logged = value(field)
        save.tap()
        let saveAnyway = app.alerts.buttons["Save"]
        if saveAnyway.waitForExistence(timeout: 1) { saveAnyway.tap() }
        XCTAssertTrue(app.staticTexts["Saved to Health"].waitForExistence(timeout: 4))
        XCTAssertFalse(save.exists)
        XCTAssertEqual(value(field), logged, accuracy: 0.001)
        snapshot(app, "42-saved")

        // Tap the number to type over it; Cancel restores.
        field.tap()
        sleep(1)
        snapshot(app, "43-focused-empty")
        field.typeText("180.4")
        XCTAssertEqual(value(field), 180.4, accuracy: 0.001)
        XCTAssertTrue(save.isEnabled)
        // The reading just saved is yours and under an hour old, so saving now replaces it.
        let replaces = app.staticTexts["quickLogReplaces"]
        XCTAssertTrue(replaces.exists)
        XCTAssertTrue(replaces.label.contains(String(format: "%.1f lb", logged)), replaces.label)
        snapshot(app, "44-typing")
        cancel.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 2))
        XCTAssertEqual(value(field), logged, accuracy: 0.001)

        // A big jump asks first; Edit goes back to the number without saving.
        field.tap()
        field.typeText(String(format: "%.1f", logged - 60))
        save.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["Save \(String(format: "%.1f", logged - 60)) lb?"].exists)
        snapshot(app, "45-big-change")
        alert.buttons["Edit"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        XCTAssertEqual(value(field), logged - 60, accuracy: 0.001)
        cancel.tap()
        XCTAssertEqual(value(field), logged, accuracy: 0.001)

        // Replace: the recent reading is swapped for the new one rather than kept alongside it.
        let replacement = start - 0.2
        field.tap()
        field.typeText(String(format: "%.1f", replacement))
        save.tap()
        if saveAnyway.waitForExistence(timeout: 1) { saveAnyway.tap() }
        XCTAssertTrue(app.staticTexts["Saved to Health"].waitForExistence(timeout: 4))
        XCTAssertEqual(value(field), replacement, accuracy: 0.001)
        app.tabBars.buttons["History"].tap()
        let rows = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' lb'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 4))
        let shown = (0..<min(rows.count, 4)).map { rows.element(boundBy: $0).label }
        XCTAssertFalse(shown.contains(String(format: "%.1f lb", logged)), "Replaced reading should be gone: \(shown)")
        XCTAssertTrue(shown.contains(String(format: "%.1f lb", replacement)), "\(shown)")
        snapshot(app, "47-history-after-replace")
    }
}
