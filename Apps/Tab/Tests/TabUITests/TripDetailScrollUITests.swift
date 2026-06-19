import XCTest

@MainActor
final class TripDetailScrollUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExpensesScrollAfterRapidSegmentSwitching() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchEnvironment["TAB_RESET_LOCAL_STORE"] = "1"
        app.launchEnvironment["TAB_SEED_DEMO"] = "1"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let lisbon = row(app, containing: "Lisbon Long Weekend")
        XCTAssertTrue(lisbon.waitForExistence(timeout: 8), "seeded trip should be listed")
        lisbon.tap()

        XCTAssertTrue(app.buttons["Expenses"].waitForExistence(timeout: 5))
        for _ in 0..<3 {
            app.buttons["Balances"].tap()
            app.buttons["Overview"].tap()
            app.buttons["Expenses"].tap()
        }

        app.swipeUp()

        XCTAssertTrue(
            app.staticTexts["Airbnb in Alfama"].waitForExistence(timeout: 3),
            "expenses should still scroll after rapid segment switching"
        )
    }

    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        let staticText = app.staticTexts.matching(predicate).firstMatch
        return staticText.exists ? staticText : button
    }
}
