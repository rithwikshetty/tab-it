import Foundation
import Testing
import TabCore
@testable import Tab

@MainActor
@Suite("Overview presenter")
struct OverviewPresenterTests {
    let you = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let marco = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let food = UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!
    let lodging = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!

    private func names(_ id: UUID) -> String { id == marco ? "Marco" : "Member" }
    private func categoryNames(_ id: UUID?) -> String {
        switch id {
        case food: return "Food & Drink"
        case lodging: return "Lodging"
        default: return "Other"
        }
    }
    private func day(_ d: Int) -> Date {
        DateComponents(calendar: .current, year: 2026, month: 3, day: d, hour: 12).date!
    }

    @Test("no summaries → empty state, no currencies")
    func empty() {
        let state = OverviewPresenter.resolve(summaries: [], currentPersonID: you, personName: names, categoryName: categoryNames)
        #expect(state.isEmpty)
        #expect(state.currencies.isEmpty)
    }

    @Test("currency option set + page order follow the summaries")
    func currencyOptions() {
        let summaries = [
            TripSpendSummary(currency: "EUR", total: 100, perPerson: [], perCategory: []),
            TripSpendSummary(currency: "JPY", total: 8000, perPerson: [], perCategory: []),
        ]
        let state = OverviewPresenter.resolve(summaries: summaries, currentPersonID: you, personName: names, categoryName: categoryNames)
        #expect(state.currencies == ["EUR", "JPY"])
        #expect(state.pages.map(\.currency) == ["EUR", "JPY"])
    }

    @Test("summary card shows total, your paid/share and your percentage")
    func summaryCard() throws {
        let summary = TripSpendSummary(
            currency: "EUR", total: 200,
            perPerson: [
                PersonSpend(personID: you, paid: 150, share: 50),
                PersonSpend(personID: marco, paid: 50, share: 150),
            ],
            perCategory: []
        )
        let page = try #require(OverviewPresenter.resolve(summaries: [summary], currentPersonID: you, personName: names, categoryName: categoryNames).pages.first)
        #expect(page.totalSpent == MoneyFormatter.formatSymbol(200, currency: "EUR"))
        #expect(page.youPaid == MoneyFormatter.formatSymbol(150, currency: "EUR"))
        #expect(page.yourShare == MoneyFormatter.formatSymbol(50, currency: "EUR"))
        #expect(page.yourSharePercent == "25% of trip spend")  // 50 / 200
    }

    @Test("person rows label the current user as You and ratio share against total")
    func personRows() throws {
        let summary = TripSpendSummary(
            currency: "EUR", total: 200,
            perPerson: [
                PersonSpend(personID: marco, paid: 50, share: 150),
                PersonSpend(personID: you, paid: 150, share: 50),
            ],
            perCategory: []
        )
        let page = try #require(OverviewPresenter.resolve(summaries: [summary], currentPersonID: you, personName: names, categoryName: categoryNames).pages.first)
        let mine = try #require(page.people.first { $0.id == you })
        #expect(mine.name == "You")
        #expect(mine.isYou)
        #expect(mine.shareFraction == 0.25)
        let marcoRow = try #require(page.people.first { $0.id == marco })
        #expect(marcoRow.name == "Marco")
        #expect(marcoRow.shareFraction == 0.75)
    }

    @Test("category rows resolve name, trip percent, and bar fraction relative to the largest")
    func categoryRows() throws {
        let summary = TripSpendSummary(
            currency: "EUR", total: 250,
            perPerson: [],
            perCategory: [
                CategorySpend(categoryID: lodging, total: 200),
                CategorySpend(categoryID: food, total: 50),
            ]
        )
        let page = try #require(OverviewPresenter.resolve(summaries: [summary], currentPersonID: you, personName: names, categoryName: categoryNames).pages.first)
        #expect(page.categories.map(\.name) == ["Lodging", "Food & Drink"])
        #expect(page.categories[0].percent == 0.8)    // 200 / 250
        #expect(page.categories[0].fraction == 1.0)   // largest
        #expect(page.categories[1].fraction == 0.25)  // 50 / 200
    }
}
