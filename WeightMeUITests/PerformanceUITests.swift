import XCTest

/// Responsiveness with a long history (15 years ≈ 5,000 readings — the size of a Lose It! export
/// going back to 2011). Fails if any interaction takes longer than a few seconds, which is how the
/// earlier Swift Charts axis hang would have shown up. Limits include XCUITest's own overhead (~1 s per tap,
/// ~3 s per swipe while it waits for scrolling to settle); measured on 2026-11-07 the 15-year and 4-year runs
/// were within 0.3 s of each other on every step, and computing all series for 15 years took ~0.1 s.
final class PerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor private func timed(_ label: String, limit: TimeInterval, _ action: () -> Void) {
        let start = Date()
        action()
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "[perf] %@: %.2f s", label, elapsed))
        XCTAssertLessThan(elapsed, limit, "\(label) took \(elapsed) s")
    }

    @MainActor private func inView(_ app: XCUIApplication) -> String {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' – '")).firstMatch.label
    }

    @MainActor func testFifteenYearsStaysResponsive() { run(years: "15") }

    /// Same steps on the default ~4-year demo, for comparison (XCUITest adds ~1 s per action).
    @MainActor func testBaselineFourYears() { run(years: "4.3") }

    @MainActor private func run(years: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoYears", years, "-chartRange", "All",
                               "-chartLayers", "(readings,average7,average30,average90,trend,monthlyRange)"]
        timed("launch to chart", limit: 12) {
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["weightChart"].firstMatch.waitForExistence(timeout: 12))
        }

        for range in ["W", "M", "3M", "6M", "Y", "2Y", "All"] {
            let before = inView(app)
            timed("switch to \(range)", limit: 3) {
                app.buttons[range].firstMatch.tap()
                _ = inView(app)   // waits for the app to go idle after the tap
            }
            if range != "All" { XCTAssertNotEqual(inView(app), before, "\(range) didn't change the range") }
        }

        app.buttons["3M"].firstMatch.tap()
        let chart = app.descendants(matching: .any)["weightChart"].firstMatch
        timed("scroll back 3 screens", limit: 15) {
            for _ in 0..<3 { chart.swipeRight(velocity: .fast) }
            _ = inView(app)
        }
        timed("pinch zoom", limit: 4) {
            chart.pinch(withScale: 0.3, velocity: -2)
            _ = inView(app)
        }

        timed("open Entries (all rows)", limit: 5) {
            app.buttons["History"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        }
        timed("scroll Entries", limit: 16) {
            for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "perf-entries"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
