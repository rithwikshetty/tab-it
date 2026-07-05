import XCTest

@MainActor
final class TripPeopleFlowUITests: XCTestCase {
    private let alexID = "22222222-2222-2222-2222-222222222222"
    private let samID = "33333333-3333-3333-3333-333333333333"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// End-to-end People sheet management: remove a member (they disappear
    /// from the member list) and repoint a pending member's email.
    func testRemoveMemberAndEditPendingEmailThroughPeopleSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "People \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let peopleButton = app.buttons["Add people"]
        XCTAssertTrue(peopleButton.waitForExistence(timeout: 5))
        peopleButton.tap()

        // Remove Alex: row → detail sheet → remove → confirm.
        let alexRow = app.buttons["people.personRow.\(alexID)"]
        XCTAssertTrue(alexRow.waitForExistence(timeout: 5))
        alexRow.tap()

        let removeButton = app.buttons["personDetail.removeButton"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
        removeButton.tap()

        let confirmRemove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(confirmRemove.waitForExistence(timeout: 5))
        confirmRemove.tap()

        // Back on the People sheet, Alex is gone; Sam is still listed.
        let samRow = app.buttons["people.personRow.\(samID)"]
        XCTAssertTrue(samRow.waitForExistence(timeout: 5))
        let alexGone = NSPredicate(format: "exists == 0")
        expectation(for: alexGone, evaluatedWith: alexRow)
        waitForExpectations(timeout: 5)

        // Repoint Sam's email and save.
        samRow.tap()
        let emailField = app.textFields["personDetail.emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        replaceText(in: emailField, with: "sam.new@test.tab")
        app.buttons["personDetail.saveEmailButton"].tap()

        // The detail sheet dismisses and the row shows the new email.
        XCTAssertTrue(app.staticTexts["sam.new@test.tab"].waitForExistence(timeout: 5))

        // The removed member stays out of the split participants for a new expense.
        app.buttons["Done"].tap()
        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()
        replaceText(in: app.textFields["expense.amountField"], with: "30")
        app.buttons["expense.paidByRow"].tap()
        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paidBy.toggle.\(samID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paidBy.toggle.\(alexID)"].exists)
    }

    // MARK: - Helpers

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let current = fieldValue(element)
        if !current.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        element.typeText(text)
    }

    private func fieldValue(_ element: XCUIElement) -> String {
        (element.value as? String) ?? ""
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
