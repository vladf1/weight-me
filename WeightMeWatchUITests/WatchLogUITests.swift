import XCTest

/// Logs a weight on the watch against the watch simulator's real HealthKit store.
///
/// The Health permission sheet is shown by a system process whose switches don't respond to XCUITest taps
/// in the watchOS 27.2 simulator (as of 2026-11-07). If access hasn't been granted, the test skips: approve it
/// once by hand in the simulator (Connect Health › Review › turn on all › Allow) and it runs fully afterwards.
final class WatchLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The watch shows Health's permission sheet from a system process, so look there as well as in the app.
    @MainActor private func approveHealthSheet(_ app: XCUIApplication) {
        let system = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let labels = ["Review", "Turn On All", "Select All", "All Recorded Data and Future Data", "Allow", "Continue", "Done", "Next"]
        for step in 0..<12 {
            sleep(1)
            if app.buttons["Log Weight"].exists { return }
            var tapped = false
            for source in [system, app] {
                // Pages list data types under an "All Requested Data Below" switch: turn it on first.
                let all = source.switches.matching(NSPredicate(format: "label BEGINSWITH 'All Requested'")).firstMatch
                if all.exists, all.isHittable, (all.value as? String) != "1" {
                    all.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()   // the switch, not its label
                    tapped = true
                    break
                }
                for label in labels {
                    let control = source.descendants(matching: .any)
                        .matching(NSPredicate(format: "label BEGINSWITH %@ AND (elementType == %d OR elementType == %d)",
                                              label, XCUIElement.ElementType.button.rawValue,
                                              XCUIElement.ElementType.cell.rawValue))
                        .firstMatch
                    if control.exists && control.isHittable && control.isEnabled {
                        control.tap()
                        tapped = true
                        break
                    }
                }
                if tapped { break }
            }
            snapshot(app, "watch-sheet-step-\(step)")
            if !tapped {
                let dump = XCTAttachment(string: system.debugDescription)
                dump.name = "carousel-hierarchy-\(step)"
                dump.lifetime = .keepAlways
                add(dump)
                system.swipeUp()
            }
        }
    }

    @MainActor func testLogWeightOnWatch() throws {
        let app = XCUIApplication()
        app.launch()

        let connect = app.buttons["Connect Health"]
        if connect.waitForExistence(timeout: 5) {
            connect.tap()
            approveHealthSheet(app)
        }

        let log = app.buttons["Log Weight"]
        guard log.waitForExistence(timeout: 10) else {
            throw XCTSkip("Health access not granted in this watch simulator; approve it once by hand (see the comment above).")
        }
        snapshot(app, "watch-home")
        log.tap()

        let increase = app.buttons["Increase"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        increase.tap()
        increase.tap()
        snapshot(app, "watch-log")
        app.buttons["Save"].tap()

        // Back on the home screen with the new weight.
        XCTAssertTrue(log.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["now"].waitForExistence(timeout: 3) || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'now' OR label CONTAINS 'second'")).firstMatch.exists,
                      "Latest weight should be the one just logged")
        snapshot(app, "watch-after-save")
    }
}
