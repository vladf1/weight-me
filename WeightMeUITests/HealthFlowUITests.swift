import XCTest

/// End-to-end tests against the simulator's real HealthKit store.
/// Run on a dedicated simulator: they write to (and clean up) Apple Health data owned by WeightMe.
/// Tests are named so XCTest runs them in order (connect → seed → import → entry editing).
final class HealthFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    @MainActor private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps through the system Health permission sheet if it appears.
    @MainActor private func approveHealthSheetIfShown(_ app: XCUIApplication) {
        // iOS 27: a "Select All N Topics" cell; older systems: "Turn On All".
        let selectAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"].firstMatch
        let turnOnAll = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Turn On All' OR label BEGINSWITH 'Select All'")).firstMatch
        if selectAll.waitForExistence(timeout: 6) {
            selectAll.tap()
        } else if turnOnAll.exists {
            turnOnAll.tap()
        } else {
            return
        }
        snapshot(app, "00b-health-sheet")
        // The confirm button is labelled "Allow" or "Continue" depending on the OS; the identifier is stable.
        // It only becomes a hittable button once the sheet is scrolled to the bottom.
        let allow = app.buttons["UIA.Health.Allow.Button"].firstMatch
        var swipes = 0
        while !(allow.exists && allow.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        if allow.exists { allow.tap() }
        _ = allow.waitForNonExistence(timeout: 5)

        // iOS 27 second step: how much history to share. WeightMe needs all of it.
        let allHistory = app.staticTexts["All Recorded Data and Future Data"].firstMatch
        if allHistory.waitForExistence(timeout: 4) {
            allHistory.tap()
            snapshot(app, "00c-health-history-scope")
            let finalAllow = app.buttons["Allow"].firstMatch
            if finalAllow.waitForExistence(timeout: 3) { finalAllow.tap() }
        }
    }

    @MainActor private func connectIfNeeded(_ app: XCUIApplication) {
        let connect = app.buttons["Connect Apple Health"]
        if connect.waitForExistence(timeout: 4) {
            snapshot(app, "00-onboarding")
            connect.tap()
            approveHealthSheetIfShown(app)
        }
    }

    // MARK: Tests

    @MainActor func test1_ConnectHealth() {
        let app = launch()
        connectIfNeeded(app)
        // Either the chart (data present) or the empty state should appear.
        let ready = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '7-day average'")).firstMatch.waitForExistence(timeout: 8)
            || app.staticTexts["No Weight Data Yet"].waitForExistence(timeout: 2)
        snapshot(app, "01-after-connect")
        XCTAssertTrue(ready, "Expected chart or empty state after connecting Health")
    }

    @MainActor func test2_SeedSampleData() {
        let app = launch(["-tab", "settings"])
        connectIfNeeded(app)
        let readings = app.staticTexts["Readings"]
        _ = readings.waitForExistence(timeout: 5)
        let seed = app.buttons["Seed Apple Health with Sample Data"]
        var swipes = 0
        while !seed.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        // Only seed once; the app also refuses to seed a store that already has data.
        let countLabel = app.staticTexts["readingsCount"]
        let existing = Int((countLabel.exists ? countLabel.label : "0").filter(\.isNumber)) ?? 0
        if existing < 100 {
            seed.tap()
            XCTAssertTrue(app.staticTexts["Seeded."].waitForExistence(timeout: 60))
        }
        snapshot(app, "02-settings-after-seed")

        let relaunched = launch(["-chartRange", "Y"])
        XCTAssertTrue(relaunched.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '7-day average'")).firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        snapshot(relaunched, "03-chart-with-health-data")
    }

    @MainActor func test3_ImportLoseItThenUndo() throws {
        let app = launch(["-openImport", "LoseIt-weights.csv"])
        let importButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Import '")).firstMatch
        guard importButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("LoseIt-weights.csv not present in the app's Documents folder")
        }
        snapshot(app, "10-import-review")
        let count = importButton.label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        XCTAssertFalse(count.isEmpty)

        importButton.tap()

        // Final check: type the count.
        let add = app.buttons["Add \(count) Entries to Apple Health"]
        XCTAssertTrue(add.waitForExistence(timeout: 6))
        XCTAssertFalse(add.isEnabled, "Final button must start disabled")
        XCTAssertFalse(app.switches.firstMatch.exists, "No acknowledgement toggle on the final check")
        let field = app.textFields["Type \(count) to confirm"]
        field.tap()
        field.typeText("1")
        XCTAssertFalse(add.isEnabled, "Wrong number must not enable import")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText(count)
        snapshot(app, "12-import-final-confirmation")
        XCTAssertTrue(add.isEnabled)
        add.tap()

        let done = app.staticTexts["Imported \(count) entries"]
        XCTAssertTrue(done.waitForExistence(timeout: 60))
        snapshot(app, "13-import-finished")

        // Undo.
        app.buttons["Undo This Import"].tap()
        let remove = app.buttons["Remove \(count) Entries"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertTrue(app.staticTexts["Import undone"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Removed \(count) entries from Apple Health."].exists)
        snapshot(app, "14-import-undone")
    }

    @MainActor func test4_LogEditDeleteEntry() {
        let app = launch(["-openAdd"])
        let field = app.textFields["Weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        field.typeText("123.4")
        snapshot(app, "20-log-weight")
        app.buttons["Save"].tap()
        // Big-change confirmation may appear, since seeded data is ~180 lb.
        let saveAnyway = app.alerts.buttons["Save"]
        if saveAnyway.waitForExistence(timeout: 2) { saveAnyway.tap() }

        // It should now be the latest reading.
        let latest = app.textFields["quickLogField"]
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertTrue(NSPredicate(format: "value == '123.4'").evaluate(with: latest)
                      || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '123.4'"), object: latest)], timeout: 8) == .completed)
        snapshot(app, "21-chart-after-log")

        // Delete it from the History tab.
        let entries = launch(["-tab", "history"])
        let row = entries.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH '123.4 lb'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.swipeLeft()
        entries.buttons["Delete"].firstMatch.tap()
        let confirm = entries.buttons["Delete 123.4 lb"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 8))
        snapshot(entries, "22-entries-after-delete")
    }
}
