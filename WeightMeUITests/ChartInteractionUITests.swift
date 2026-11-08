import XCTest

/// Chart gestures on demo data (no HealthKit needed).
final class ChartInteractionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func inViewRange(_ app: XCUIApplication) -> String {
        // The "In View" header shows "Mon d, yy – Mon d, yy".
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' – '")).firstMatch.label
    }

    /// Choosing a range shows its most recent stretch, even after scrolling back in time.
    @MainActor func testPickingRangeShowsLatest() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-chartRange", "3M", "-chartLayers", "(readings,average7,trend)"]
        app.launch()

        let chart = app.descendants(matching: .any)["weightChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 6))
        let latestEnd = inViewRange(app).components(separatedBy: " – ").last!

        chart.swipeRight(velocity: .slow)
        chart.swipeRight(velocity: .slow)
        sleep(2)
        XCTAssertNotEqual(inViewRange(app).components(separatedBy: " – ").last, latestEnd, "Should have scrolled back")
        XCTAssertTrue(app.buttons["Reset"].waitForExistence(timeout: 3), "Reset shows when scrolled back")

        for range in ["Y", "M", "6M"] {
            app.buttons[range].tap()
            sleep(1)
            XCTAssertEqual(inViewRange(app).components(separatedBy: " – ").last, latestEnd, "\(range) should end at the latest")
            chart.swipeRight(velocity: .slow)
            sleep(1)
        }
        snapshot(app, "32-range-after-scroll")
        app.buttons["Reset"].tap()
        sleep(1)
        XCTAssertEqual(inViewRange(app).components(separatedBy: " – ").last, latestEnd, "Reset returns to the latest")
        XCTAssertTrue(app.buttons["Reset"].waitForNonExistence(timeout: 3))
    }

    @MainActor func testScrollZoomAndInspect() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-chartRange", "3M", "-chartLayers", "(readings,average7,trend)"]
        app.launch()

        let chart = app.descendants(matching: .any)["weightChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 6))
        let initialRange = inViewRange(app)

        // Drag right = scroll back in time; the "In View" stats follow.
        chart.swipeRight(velocity: .slow)
        sleep(2)
        XCTAssertNotEqual(inViewRange(app), initialRange, "Scrolling should change the visible range")
        snapshot(app, "30-scrolled-back")

        // Pinch to zoom in → a Reset button appears; it restores the preset range.
        chart.pinch(withScale: 2.5, velocity: 2)
        let reset = app.buttons["Reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3), "Pinch should produce a custom zoom")
        snapshot(app, "31-zoomed")
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 3))

        // Press and hold to inspect a reading (must not crash; callout appears while holding).
        let point = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        point.press(forDuration: 1.2)

        // Deterministic callout screenshot via the debug preselection hook.
        app.terminate()
        app.launchArguments = ["-demo", "-chartRange", "M", "-chartLayers", "(readings,average7,trend)", "-selectDaysAgo", "12"]
        app.launch()
        // Chart annotations aren't exposed to accessibility individually; verify visually.
        XCTAssertTrue(app.descendants(matching: .any)["weightChart"].firstMatch.waitForExistence(timeout: 6))
        sleep(2)
        snapshot(app, "32-inspect-callout")
    }
}
