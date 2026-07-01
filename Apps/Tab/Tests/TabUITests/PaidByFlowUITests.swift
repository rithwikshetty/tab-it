import XCTest

@MainActor
final class PaidByFlowUITests: XCTestCase {
    private let currentUserID = "11111111-1111-1111-1111-111111111111"
    private let alexID = "22222222-2222-2222-2222-222222222222"
    private let samID = "33333333-3333-3333-3333-333333333333"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExactPaidByLedgerSurvivesReturningFromPaidByEditor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Paid By \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        let tripNameField = firstExisting([
            app.textFields["newTrip.nameField"],
            app.textFields["Lisbon weekend"],
        ])
        replaceText(in: tripNameField, with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "100")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Dinner")
        app.buttons["expense.paidByRow"].tap()

        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        app.buttons["paidBy.toggle.\(alexID)"].tap()
        app.buttons["paidBy.toggle.\(samID)"].tap()
        app.buttons["paymentSplit.payerModePill"].tap()
        app.buttons["Exact amounts"].tap()

        let currentUserAmount = app.textFields["paidBy.exactAmount.\(currentUserID)"]
        let alexAmount = app.textFields["paidBy.exactAmount.\(alexID)"]
        let samAmount = app.textFields["paidBy.exactAmount.\(samID)"]
        replaceText(in: currentUserAmount, with: "60")
        XCTAssertEqual(fieldValue(currentUserAmount), "60")
        replaceText(in: alexAmount, with: "30")
        XCTAssertEqual(fieldValue(alexAmount), "30")
        replaceText(in: samAmount, with: "10")
        XCTAssertEqual(fieldValue(samAmount), "10")
        XCTAssertEqual(fieldValue(currentUserAmount), "60")
        XCTAssertEqual(fieldValue(alexAmount), "30")
        XCTAssertEqual(fieldValue(samAmount), "10")
        app.navigationBars["Payment & Split"].buttons["Done"].tap()

        let paidBySummary = app.staticTexts["expense.paidBySummary"]
        XCTAssertTrue(paidBySummary.waitForExistence(timeout: 5))
        XCTAssertEqual(paidBySummary.label, "3 people")

        app.buttons["expense.paidByRow"].tap()
        XCTAssertTrue(app.textFields["paidBy.exactAmount.\(currentUserID)"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app.textFields["paidBy.exactAmount.\(currentUserID)"]), "60.00")
        XCTAssertEqual(fieldValue(app.textFields["paidBy.exactAmount.\(alexID)"]), "30.00")
        XCTAssertEqual(fieldValue(app.textFields["paidBy.exactAmount.\(samID)"]), "10.00")
    }

    func testMockAuthTripSeedsPeopleAndExactAmountTapSelectsExistingValue() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Seeded \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "100")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Dinner")
        app.buttons["expense.paidByRow"].tap()

        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paidBy.toggle.\(alexID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paidBy.toggle.\(samID)"].waitForExistence(timeout: 5))

        app.buttons["split.toggle.\(alexID)"].tap()
        app.buttons["paymentSplit.splitModePill"].tap()
        app.buttons["Exact amounts"].tap()

        let currentUserSplit = app.textFields["split.exactAmount.\(currentUserID)"]
        XCTAssertTrue(currentUserSplit.waitForExistence(timeout: 5))
        currentUserSplit.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        currentUserSplit.typeText("40")
        XCTAssertEqual(fieldValue(currentUserSplit), "40")
    }

    func testEditExpenseFromDetailOpensEditForm() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Edit Flow \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "24.50")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Lunch")
        app.navigationBars["New expense"].buttons["Save"].tap()

        let expenseRow = app.staticTexts["Lunch"].firstMatch
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.tap()

        let actionsButton = app.buttons["expenseDetail.actionsButton"]
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        let editButton = app.buttons["expenseDetail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["expense.descriptionField"].waitForExistence(timeout: 5))
    }

    func testPaymentMethodDropdownSelectionPersistsToDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Payment Method \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "18.25")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Coffee")

        let paymentMethodMenu = app.buttons["expense.paymentMethodMenu"]
        XCTAssertTrue(paymentMethodMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(paymentMethodMenu.label, "Card")
        paymentMethodMenu.tap()
        app.buttons["Cash"].tap()
        XCTAssertEqual(paymentMethodMenu.label, "Cash")

        app.navigationBars["New expense"].buttons["Save"].tap()

        let expenseRow = app.staticTexts["Coffee"].firstMatch
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.tap()

        XCTAssertTrue(app.staticTexts["Paid via"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cash"].waitForExistence(timeout: 5))
    }

    func testSharesSplitSavesAndRoundTripsThroughEdit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Shares \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "30")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Pints")
        app.buttons["expense.paidByRow"].tap()

        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        app.buttons["paymentSplit.splitModePill"].tap()
        app.buttons["Shares"].tap()

        // Everyone starts at 1 share; a full pint for Alex is 2.
        let currentUserShare = app.textFields["split.shareUnits.\(currentUserID)"]
        let alexShare = app.textFields["split.shareUnits.\(alexID)"]
        XCTAssertTrue(currentUserShare.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(currentUserShare), "1")
        XCTAssertEqual(fieldValue(alexShare), "1")
        replaceText(in: alexShare, with: "2")
        XCTAssertEqual(fieldValue(alexShare), "2")
        XCTAssertTrue(app.staticTexts["4 shares total"].waitForExistence(timeout: 5))
        app.navigationBars["Payment & Split"].buttons["Done"].tap()

        // Back on the entry form the split row reflects shares and keeps the weights.
        XCTAssertTrue(app.staticTexts["Split by shares"].waitForExistence(timeout: 5))
        let entryAlexShare = app.textFields["expense.shareUnits.\(alexID)"]
        XCTAssertTrue(entryAlexShare.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(entryAlexShare), "2")

        app.navigationBars["New expense"].buttons["Save"].tap()

        let expenseRow = app.staticTexts["Pints"].firstMatch
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.tap()

        XCTAssertTrue(app.staticTexts["shares · 3 ways"].waitForExistence(timeout: 5))

        let actionsButton = app.buttons["expenseDetail.actionsButton"]
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()
        let editButton = app.buttons["expenseDetail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        // Editing restores the stored share weights, not just amounts.
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        let editedAlexShare = app.textFields["expense.shareUnits.\(alexID)"]
        XCTAssertTrue(editedAlexShare.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(editedAlexShare), "2")
        XCTAssertEqual(fieldValue(app.textFields["expense.shareUnits.\(currentUserID)"]), "1")
    }

    func testPercentageSplitSavesAndRoundTripsThroughEdit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Percent \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "80")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Taxi")
        app.buttons["expense.paidByRow"].tap()

        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        app.buttons["paymentSplit.splitModePill"].tap()
        app.buttons["Percentages"].tap()

        // Three mock members seed 33.34/33.33/33.33; rework to 50/25/25.
        let currentUserPercent = app.textFields["split.percentage.\(currentUserID)"]
        let alexPercent = app.textFields["split.percentage.\(alexID)"]
        let samPercent = app.textFields["split.percentage.\(samID)"]
        XCTAssertTrue(currentUserPercent.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(currentUserPercent), "33.34")
        replaceText(in: currentUserPercent, with: "50")
        replaceText(in: alexPercent, with: "25")
        replaceText(in: samPercent, with: "25")
        XCTAssertTrue(app.staticTexts["Total 100%"].waitForExistence(timeout: 5))
        app.navigationBars["Payment & Split"].buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Split by percentages"].waitForExistence(timeout: 5))
        app.navigationBars["New expense"].buttons["Save"].tap()

        let expenseRow = app.staticTexts["Taxi"].firstMatch
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.tap()

        XCTAssertTrue(app.staticTexts["percentage · 3 ways"].waitForExistence(timeout: 5))

        let actionsButton = app.buttons["expenseDetail.actionsButton"]
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()
        let editButton = app.buttons["expenseDetail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        // Editing restores the stored percentages.
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        let editedUserPercent = app.textFields["expense.percentage.\(currentUserID)"]
        XCTAssertTrue(editedUserPercent.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(editedUserPercent), "50")
        XCTAssertEqual(fieldValue(app.textFields["expense.percentage.\(alexID)"]), "25")
    }

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

    private func firstExisting(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("No matching element appeared")
        return elements[0]
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
