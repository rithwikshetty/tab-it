import XCTest

@MainActor
final class ActivityFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Seeded feed: leading swipe marks one row read, trailing swipe deletes
    /// another, leaving the tab auto-marks the rest read, and both the read
    /// state and the deletion survive a relaunch (without reseeding).
    /// Read state is asserted via each row's accessibility value.
    func testSwipeReadSwipeDeleteAutoReadOnLeaveAndPersist() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchEnvironment["TAB_SEED_ACTIVITY"] = "1"
        app.launchEnvironment["TAB_START_TAB"] = "activity"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 8))

        func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
            app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        func value(_ element: XCUIElement) -> String {
            (element.value as? String) ?? ""
        }

        // Leading swipe (right) marks an unread row read.
        let dinnerRow = row(app, containing: "Beach dinner")
        XCTAssertTrue(dinnerRow.waitForExistence(timeout: 5))
        XCTAssertEqual(value(dinnerRow), "Unread")
        dinnerRow.swipeRight()

        let markRead = app.buttons["Mark as read"]
        XCTAssertTrue(markRead.waitForExistence(timeout: 5))
        markRead.tap()
        XCTAssertTrue(markRead.waitForNonExistence(timeout: 3))
        XCTAssertEqual(value(dinnerRow), "Read")

        // Trailing swipe (left) deletes a row: it leaves the feed entirely.
        let paymentRow = row(app, containing: "recorded a payment")
        XCTAssertTrue(paymentRow.waitForExistence(timeout: 5))
        paymentRow.swipeLeft()

        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(paymentRow.waitForNonExistence(timeout: 5))

        // Leaving the tab marks everything else read automatically.
        let taxiRow = row(app, containing: "Taxi to airport")
        XCTAssertTrue(taxiRow.waitForExistence(timeout: 5))
        XCTAssertEqual(value(taxiRow), "Unread")

        app.tabBars.buttons["Trips"].tap()
        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 5))

        XCTAssertTrue(taxiRow.waitForExistence(timeout: 5))
        XCTAssertEqual(value(taxiRow), "Read")

        // Relaunch WITHOUT the seed flag: rows stay read and the deleted row
        // must not be resurrected.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        relaunched.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        relaunched.launchEnvironment["TAB_START_TAB"] = "activity"
        relaunched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        relaunched.launch()

        XCTAssertTrue(relaunched.staticTexts["Activity"].waitForExistence(timeout: 8))
        let relaunchedDinner = row(relaunched, containing: "Beach dinner")
        XCTAssertTrue(relaunchedDinner.waitForExistence(timeout: 5))
        XCTAssertEqual(value(relaunchedDinner), "Read")
        XCTAssertFalse(row(relaunched, containing: "recorded a payment").exists)
    }
}
