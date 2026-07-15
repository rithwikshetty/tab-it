import Testing
import Foundation
@testable import Tab
@testable import TabCore

@MainActor
@Suite("Friends presenter")
struct FriendsPresenterTests {
    private let meUser   = UUID(uuidString: "AAAAAAAA-0000-0000-0000-0000000000A0")!
    private let bobUser  = UUID(uuidString: "BBBBBBBB-0000-0000-0000-0000000000B0")!
    private let carolUser = UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000C0")!

    private let meGoa  = UUID(uuidString: "00000000-0000-0000-00A0-000000000001")!
    private let bobGoa = UUID(uuidString: "00000000-0000-0000-00B0-000000000001")!
    private let carolGoa = UUID(uuidString: "00000000-0000-0000-00C0-000000000001")!
    private let meNG   = UUID(uuidString: "00000000-0000-0000-00A0-000000000002")!
    private let bobNG  = UUID(uuidString: "00000000-0000-0000-00B0-000000000002")!
    private let meCarolNG = UUID(uuidString: "00000000-0000-0000-00A0-000000000003")!
    private let carolNG   = UUID(uuidString: "00000000-0000-0000-00C0-000000000003")!

    private let when = Date(timeIntervalSince1970: 1_780_000_000)

    private func person(_ id: UUID, userID: UUID?, name: String, email: String, trip: TripEntity) -> TripPersonEntity {
        TripPersonEntity(id: id, userID: userID, email: email, displayName: name, trip: trip,
                         joinedAt: userID == nil ? nil : when)
    }

    /// Goa trip {me, Bob}: I paid 40, split equally → Bob owes me 20 GBP.
    private func goaTrip() -> TripEntity {
        let goa = TripEntity(name: "Goa", kind: "trip", createdByID: meUser)
        goa.people = [
            person(meGoa, userID: meUser, name: "Me", email: "me@x.com", trip: goa),
            person(bobGoa, userID: bobUser, name: "Bob", email: "bob@x.com", trip: goa),
        ]
        let e = ExpenseEntity(amount: 40, currency: "GBP", descriptionText: "Hotel", expenseDate: when, createdByID: meUser, trip: goa)
        e.payments = [PaymentEntity(tripPersonID: meGoa, amountPaid: 40, paymentModeRaw: "equal", expense: e)]
        e.splits = [
            ExpenseSplitEntity(tripPersonID: meGoa, amountOwed: 20, splitTypeRaw: "equal", expense: e),
            ExpenseSplitEntity(tripPersonID: bobGoa, amountOwed: 20, splitTypeRaw: "equal", expense: e),
        ]
        goa.expenses = [e]
        return goa
    }

    /// Non-group {me, Bob}: Bob paid 10, split equally → I owe Bob 5 GBP.
    private func bobNonGroup() -> TripEntity {
        let ng = TripEntity(name: "", kind: "non_group", memberSignature: "bob@x.com|me@x.com", createdByID: meUser)
        ng.people = [
            person(meNG, userID: meUser, name: "Me", email: "me@x.com", trip: ng),
            person(bobNG, userID: bobUser, name: "Bob", email: "bob@x.com", trip: ng),
        ]
        let e = ExpenseEntity(amount: 10, currency: "GBP", descriptionText: "Drinks", expenseDate: when, createdByID: bobUser, trip: ng)
        e.payments = [PaymentEntity(tripPersonID: bobNG, amountPaid: 10, paymentModeRaw: "equal", expense: e)]
        e.splits = [
            ExpenseSplitEntity(tripPersonID: meNG, amountOwed: 5, splitTypeRaw: "equal", expense: e),
            ExpenseSplitEntity(tripPersonID: bobNG, amountOwed: 5, splitTypeRaw: "equal", expense: e),
        ]
        ng.expenses = [e]
        return ng
    }

    /// Three-person trip: I owe Bob 10 and Bob owes Carol 10, so I owe Carol 10.
    private func redirectedTrip() -> TripEntity {
        let trip = TripEntity(name: "Redirected", kind: "trip", createdByID: meUser)
        trip.people = [
            person(meGoa, userID: meUser, name: "Me", email: "me@x.com", trip: trip),
            person(bobGoa, userID: bobUser, name: "Bob", email: "bob@x.com", trip: trip),
            person(carolGoa, userID: carolUser, name: "Carol", email: "carol@x.com", trip: trip),
        ]

        let bobExpense = ExpenseEntity(
            amount: 20, currency: "GBP", descriptionText: "Bob expense",
            expenseDate: when, createdByID: bobUser, trip: trip
        )
        bobExpense.payments = [
            PaymentEntity(tripPersonID: bobGoa, amountPaid: 20, paymentModeRaw: "equal", expense: bobExpense),
        ]
        bobExpense.splits = [
            ExpenseSplitEntity(tripPersonID: meGoa, amountOwed: 10, splitTypeRaw: "equal", expense: bobExpense),
            ExpenseSplitEntity(tripPersonID: bobGoa, amountOwed: 10, splitTypeRaw: "equal", expense: bobExpense),
        ]

        let carolExpense = ExpenseEntity(
            amount: 20, currency: "GBP", descriptionText: "Carol expense",
            expenseDate: when, createdByID: carolUser, trip: trip
        )
        carolExpense.payments = [
            PaymentEntity(tripPersonID: carolGoa, amountPaid: 20, paymentModeRaw: "equal", expense: carolExpense),
        ]
        carolExpense.splits = [
            ExpenseSplitEntity(tripPersonID: bobGoa, amountOwed: 10, splitTypeRaw: "equal", expense: carolExpense),
            ExpenseSplitEntity(tripPersonID: carolGoa, amountOwed: 10, splitTypeRaw: "equal", expense: carolExpense),
        ]

        trip.expenses = [bobExpense, carolExpense]
        return trip
    }

    @Test("a friend nets across a trip and a non-group container into one line")
    func netsAcrossContainers() throws {
        let state = FriendsPresenter.list(trips: [goaTrip(), bobNonGroup()], currentUserID: meUser)

        #expect(state.active.count == 1)
        let bob = try #require(state.active.first)
        #expect(bob.displayName == "Bob")
        #expect(bob.lines.count == 1)
        let line = try #require(bob.lines.first)
        #expect(line.currency == "GBP")
        #expect(line.isPositive)                 // Bob owes me (20 - 5 = 15)
        #expect(line.amount.contains("15"))
    }

    @Test("the current user is never listed as their own friend")
    func excludesSelf() {
        let state = FriendsPresenter.list(trips: [goaTrip()], currentUserID: meUser)
        #expect(state.active.allSatisfy { $0.friend != .user(meUser) })
        #expect(state.settled.allSatisfy { $0.friend != .user(meUser) })
    }

    @Test("containers without the current user are ignored")
    func ignoresContainersWithoutCurrentUser() {
        let otherTrip = TripEntity(name: "Other", kind: "trip", createdByID: bobUser)
        otherTrip.people = [
            person(UUID(), userID: bobUser, name: "Bob", email: "bob@x.com", trip: otherTrip),
            person(UUID(), userID: carolUser, name: "Carol", email: "carol@x.com", trip: otherTrip),
        ]

        let state = FriendsPresenter.list(trips: [otherTrip], currentUserID: meUser)

        #expect(state.active.isEmpty)
        #expect(state.settled.isEmpty)
    }

    @Test("overall banner sums you-are-owed per currency")
    func overallBanner() throws {
        let state = FriendsPresenter.list(trips: [goaTrip(), bobNonGroup()], currentUserID: meUser)
        let gbp = try #require(state.overall.first { $0.currency == "GBP" })
        #expect(gbp.youAreOwed == 15)
        #expect(gbp.youOwe == 0)
    }

    @Test("friend detail breaks the net out by source")
    func detailSources() throws {
        let detail = try #require(
            FriendsPresenter.detail(trips: [goaTrip(), bobNonGroup()], currentUserID: meUser, friend: .user(bobUser))
        )
        #expect(detail.displayName == "Bob")
        #expect(detail.overall.first?.isPositive == true)

        // Two sources: Goa (Bob owes you 20) and Non-group (you owe 5).
        #expect(detail.sources.count == 2)
        let goa = try #require(detail.sources.first { $0.sourceName == "Goa" })
        #expect(goa.isPositive)               // owes you
        #expect(goa.amount.contains("20"))
        let ng = try #require(detail.sources.first { $0.isNonGroup })
        #expect(ng.sourceName == "Non-group")
        #expect(!ng.isPositive)               // you owe
        #expect(ng.amount.contains("5"))
    }

    @Test("friend balance and source suggestion reflect a redirected three-person debt")
    func redirectedFriendBalance() throws {
        let trip = redirectedTrip()
        let state = FriendsPresenter.list(trips: [trip], currentUserID: meUser)
        let carol = try #require(state.active.first { $0.friend == .user(carolUser) })
        let line = try #require(carol.lines.first)
        #expect(!line.isPositive)
        #expect(line.amount.contains("10"))

        let detail = try #require(
            FriendsPresenter.detail(trips: [trip], currentUserID: meUser, friend: .user(carolUser))
        )
        let source = try #require(detail.sources.first)
        #expect(source.amount.contains("10"))
        #expect(source.suggestion.fromPersonID == meGoa)
        #expect(source.suggestion.toPersonID == carolGoa)
        #expect(source.suggestion.amount == 10)
        #expect(source.suggestion.currency == "GBP")
    }

    @Test("friend detail timeline tags each shared item with its source")
    func detailTimeline() throws {
        let detail = try #require(
            FriendsPresenter.detail(trips: [goaTrip(), bobNonGroup()], currentUserID: meUser, friend: .user(bobUser))
        )
        let sources = Set(detail.timeline.flatMap { $0.entries.map(\.sourceName) })
        #expect(sources.contains("Goa"))
        #expect(sources.contains("Non-group"))
    }

    @Test("a pending email-only participant shows as a pending friend")
    func pendingFriend() throws {
        let ng = TripEntity(name: "", kind: "non_group", memberSignature: "carol@x.com|me@x.com", createdByID: meUser)
        ng.people = [
            person(meCarolNG, userID: meUser, name: "Me", email: "me@x.com", trip: ng),
            person(carolNG, userID: nil, name: "Carol", email: "carol@x.com", trip: ng),
        ]
        let e = ExpenseEntity(amount: 8, currency: "GBP", descriptionText: "Cab", expenseDate: when, createdByID: meUser, trip: ng)
        e.payments = [PaymentEntity(tripPersonID: meCarolNG, amountPaid: 8, paymentModeRaw: "equal", expense: e)]
        e.splits = [
            ExpenseSplitEntity(tripPersonID: meCarolNG, amountOwed: 4, splitTypeRaw: "equal", expense: e),
            ExpenseSplitEntity(tripPersonID: carolNG, amountOwed: 4, splitTypeRaw: "equal", expense: e),
        ]
        ng.expenses = [e]

        let state = FriendsPresenter.list(trips: [ng], currentUserID: meUser)
        let carol = try #require(state.active.first { $0.displayName == "Carol" })
        #expect(carol.isPending)
        #expect(carol.friend == .email("carol@x.com"))
        #expect(carol.lines.first?.isPositive == true)   // Carol owes me 4
    }
}
