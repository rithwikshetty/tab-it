import XCTest

@MainActor
final class FriendsFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTripsAddExpenseOpensPeopleFirstPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["trips.addButton"].waitForExistence(timeout: 5))

        let fab = app.buttons["trips.addExpenseButton"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(fab))
        fab.tap()

        XCTAssertTrue(app.navigationBars["New expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newExpense.groupMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["newExpense.searchField"].waitForExistence(timeout: 5))
    }

    /// People-first global add: from Friends, add an expense with someone by email
    /// (no trip), then confirm the friend + balance appear and the friend-detail
    /// screen breaks the balance out by source.
    func testPeopleFirstNonGroupExpenseCreatesFriendAndDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchEnvironment["TAB_START_TAB"] = "friends"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        // Unique counterpart so reruns don't collide in the persisted store.
        let suffix = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        let email = "uitest\(suffix)@tab.local"
        let friendName = "Uitest\(suffix)"

        XCTAssertTrue(app.staticTexts["Friends"].waitForExistence(timeout: 8))

        let fab = app.buttons["friends.addButton"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(fab))
        fab.tap()

        // People-first picker: enter an email and invite them.
        let search = app.textFields["newExpense.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        replaceText(in: search, with: email)

        let invite = app.buttons["newExpense.inviteButton"]
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
        invite.tap()

        app.navigationBars["New expense"].buttons["Next"].tap()

        // Expense form, scoped to the resolved non-group container.
        let amount = app.textFields["expense.amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 8))
        replaceText(in: amount, with: "20")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Tapas")
        app.navigationBars["New expense"].buttons["Save"].tap()

        // Back on Friends, the new counterpart now owes the current user.
        // The row is a Button, so its child Texts collapse into the button label.
        let friendRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", friendName)
        ).firstMatch
        XCTAssertTrue(friendRow.waitForExistence(timeout: 8), "new non-group friend should appear on Friends")
        // The row label also proves the balance (the counterpart owes the current user).
        XCTAssertTrue(friendRow.label.localizedCaseInsensitiveContains("owes you"))
        friendRow.tap()

        // Friend detail breaks the balance out by source (the non-group context).
        // SectionHeaderText renders titles uppercased.
        XCTAssertTrue(app.staticTexts["BALANCE BY SOURCE"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Non-group")).firstMatch.exists,
            "friend detail should list the non-group source"
        )
    }

    // MARK: - Helpers

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let current = (element.value as? String) ?? ""
        if !current.isEmpty, current != element.placeholderValue {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        element.typeText(text)
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.isHittable
    }
}

/// Walks the demo-seeded app and captures full-screen marketing screenshots as
/// keep-always attachments. Not a regression test — run on demand:
///   xcodebuild test … -only-testing:TabUITests/ScreenshotTourUITests
@MainActor
final class ScreenshotTourUITests: XCTestCase {
    func testCaptureMarketingScreenshots() throws {
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
        snap(app, "01-trips")

        lisbon.tap()
        let pasteis = row(app, containing: "Pastéis de Belém")
        XCTAssertTrue(pasteis.waitForExistence(timeout: 8))
        snap(app, "02-trip-detail")

        let airbnb = row(app, containing: "Airbnb in Alfama")
        for _ in 0..<3 where !airbnb.exists {
            app.swipeUp()
            sleepBriefly()
        }
        XCTAssertTrue(airbnb.waitForExistence(timeout: 8))

        airbnb.tap()
        XCTAssertTrue(app.otherElements.firstMatch.waitForExistence(timeout: 8))
        snap(app, "03-expense-detail")

        // Pop back to the root so the tab bar is visible again.
        app.navigationBars.buttons.firstMatch.tap()
        sleepBriefly()
        app.navigationBars.buttons.firstMatch.tap()

        switchTab(app, "Friends")
        snap(app, "04-friends")

        switchTab(app, "Activity")
        snap(app, "05-activity")
    }

    /// iOS 18 SwiftUI tab bars don't always vend a TabBar element; fall back
    /// to a plain button match.
    private func switchTab(_ app: XCUIApplication, _ name: String) {
        let inBar = app.tabBars.buttons[name]
        let plain = app.buttons[name]
        let target = inBar.waitForExistence(timeout: 2) ? inBar : plain
        XCTAssertTrue(target.waitForExistence(timeout: 5), "tab \(name) should exist")
        target.tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
        sleepBriefly()
    }

    /// Rows render as Buttons whose child Texts collapse into the label; fall
    /// back to a StaticText match for plain rows.
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        let staticText = app.staticTexts.matching(predicate).firstMatch
        return staticText.exists ? staticText : button
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        sleepBriefly()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Let in-flight transitions and async images settle before capturing.
    private func sleepBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }
}
