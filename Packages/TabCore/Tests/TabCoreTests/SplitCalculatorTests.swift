import Testing
import Foundation
@testable import TabCore

@Suite("SplitCalculator")
struct SplitCalculatorTests {
    // Stable UUIDs so the remainder-distribution order is deterministic across runs.
    // Lexicographic order: alice < bob < charlie.
    let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let charlie = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    // MARK: equal

    @Test("equal split: even total, two-way")
    func equalEvenTwoWay() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 30,
            currency: "EUR",
            participants: [alice, bob],
            splitType: .equal
        )
        #expect(splits.count == 2)
        #expect(splits.allSatisfy { $0.amountOwed == 15 })
        #expect(splits.allSatisfy { $0.splitType == .equal })
        #expect(Set(splits.map(\.participantID)) == [alice, bob])
    }

    @Test("equal split: $10/3 distributes 1-cent remainder to first sorted participant")
    func equalThreeWayWithRemainder() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 10,
            currency: "USD",
            participants: [bob, charlie, alice],  // intentionally unsorted
            splitType: .equal
        )
        #expect(splits.count == 3)
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == 10)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        // alice has the lowest UUID, so alice gets the extra cent
        #expect(byUser[alice] == Decimal(string: "3.34"))
        #expect(byUser[bob] == Decimal(string: "3.33"))
        #expect(byUser[charlie] == Decimal(string: "3.33"))
    }

    @Test("equal split: $1/3 — 1 cent goes to lowest UUID")
    func equalDollarThreeWay() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 1,
            currency: "USD",
            participants: [alice, bob, charlie],
            splitType: .equal
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == 1)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "0.34"))
        #expect(byUser[bob] == Decimal(string: "0.33"))
        #expect(byUser[charlie] == Decimal(string: "0.33"))
    }

    @Test("equal split: single participant gets the whole amount")
    func equalSingleParticipant() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 50,
            currency: "EUR",
            participants: [alice],
            splitType: .equal
        )
        #expect(splits.count == 1)
        #expect(splits[0].amountOwed == 50)
        #expect(splits[0].participantID == alice)
    }

    @Test("equal split: zero amount → all participants owe zero")
    func equalZeroAmount() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 0,
            currency: "EUR",
            participants: [alice, bob, charlie],
            splitType: .equal
        )
        #expect(splits.allSatisfy { $0.amountOwed == 0 })
    }

    @Test("equal split: empty participants throws emptyParticipants")
    func equalEmptyParticipantsThrows() {
        #expect(throws: SplitCalculatorError.emptyParticipants) {
            _ = try SplitCalculator.calculate(
                totalAmount: 10,
                currency: "EUR",
                participants: [],
                splitType: .equal
            )
        }
    }

    @Test("equal split: 2-cent remainder distributes to two lowest UUIDs")
    func equalTwoCentRemainder() throws {
        // $1.00 / 3 = 33.33¢ each, remainder 1¢? Let's check:
        // Actually need a case with 2¢ remainder. $0.05 / 3 = 1¢ each, 2¢ remainder.
        let splits = try SplitCalculator.calculate(
            totalAmount: Decimal(string: "0.05")!,
            currency: "USD",
            participants: [alice, bob, charlie],
            splitType: .equal
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == Decimal(string: "0.05"))
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "0.02"))
        #expect(byUser[bob] == Decimal(string: "0.02"))
        #expect(byUser[charlie] == Decimal(string: "0.01"))
    }

    @Test("equal split: JPY uses whole-yen minor units")
    func equalJPYUsesWholeUnits() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 101,
            currency: "JPY",
            participants: [bob, alice],
            splitType: .equal
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 51)
        #expect(byUser[bob] == 50)
    }

    @Test("equal split: KWD uses three decimal minor units")
    func equalKWDUsesThreeDecimals() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: Decimal(string: "1.001")!,
            currency: "KWD",
            participants: [alice, bob],
            splitType: .equal
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "0.501"))
        #expect(byUser[bob] == Decimal(string: "0.500"))
    }

    @Test("equal split: rejects amounts with too many currency fraction digits")
    func equalRejectsInvalidCurrencyPrecision() {
        #expect(throws: SplitCalculatorError.amountHasTooManyFractionDigits(currency: "JPY", maximumFractionDigits: 0)) {
            _ = try SplitCalculator.calculate(
                totalAmount: Decimal(string: "10.25")!,
                currency: "JPY",
                participants: [alice, bob],
                splitType: .equal
            )
        }
    }

    // MARK: exact

    @Test("exact split: amounts sum to total")
    func exactValid() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 100,
            currency: "EUR",
            participants: [alice, bob, charlie],
            splitType: .exact,
            exactAmounts: [alice: 40, bob: 30, charlie: 30]
        )
        #expect(splits.count == 3)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 40)
        #expect(byUser[bob] == 30)
        #expect(byUser[charlie] == 30)
        #expect(splits.allSatisfy { $0.splitType == .exact })
    }

    @Test("exact split: amounts don't sum to total throws")
    func exactSumMismatchThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .exact,
                exactAmounts: [alice: 50, bob: 30]
            )
        }
    }

    @Test("exact split: missing a participant amount throws")
    func exactMissingParticipantThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob, charlie],
                splitType: .exact,
                exactAmounts: [alice: 50, bob: 50]
            )
        }
    }

    @Test("exact split: extra non-participant amount throws")
    func exactExtraNonParticipantThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .exact,
                exactAmounts: [alice: 40, bob: 30, charlie: 30]
            )
        }
    }

    @Test("exact split: nil exactAmounts throws")
    func exactNilAmountsThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .exact,
                exactAmounts: nil
            )
        }
    }

    // MARK: unsupported

    @Test("unsupported types throw unsupportedSplitType",
          arguments: [SplitType.percentage, .shares, .adjustment])
    func unsupportedTypes(_ type: SplitType) {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice],
                splitType: type
            )
        }
    }

    // MARK: duplicate participants

    @Test("equal split: duplicate participant throws")
    func equalSplitDuplicateParticipantThrows() {
        #expect(throws: SplitCalculatorError.duplicateParticipant(alice)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, alice, bob],
                splitType: .equal
            )
        }
    }

    @Test("exact split: duplicate participant throws instead of double-counting")
    func exactSplitDuplicateParticipantThrows() {
        // Without the guard, [A, A, B] with amounts A:50 B:50 passes the
        // set-based validation but emits splits totalling 150.
        #expect(throws: SplitCalculatorError.duplicateParticipant(alice)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, alice, bob],
                splitType: .exact,
                exactAmounts: [alice: 50, bob: 50]
            )
        }
    }

    // MARK: shares

    @Test("shares split: whole shares divide proportionally")
    func sharesWholeProportional() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 30,
            currency: "EUR",
            participants: [alice, bob],
            splitType: .shares,
            shares: [alice: 2, bob: 1]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 20)
        #expect(byUser[bob] == 10)
        #expect(splits.allSatisfy { $0.splitType == .shares })
    }

    @Test("shares split: fractional shares (half pint = 0.5)")
    func sharesFractional() throws {
        // The group-chat case: 2 full pints + 2 halves over a 30 bill.
        let dave = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!
        let splits = try SplitCalculator.calculate(
            totalAmount: 30,
            currency: "GBP",
            participants: [alice, bob, charlie, dave],
            splitType: .shares,
            shares: [alice: 1, bob: 1, charlie: Decimal(string: "0.5")!, dave: Decimal(string: "0.5")!]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 10)
        #expect(byUser[bob] == 10)
        #expect(byUser[charlie] == 5)
        #expect(byUser[dave] == 5)
    }

    @Test("shares split: carries the share weight on each split")
    func sharesCarriesWeights() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 30,
            currency: "EUR",
            participants: [alice, bob],
            splitType: .shares,
            shares: [alice: 2, bob: 1]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.shareUnits) })
        #expect(byUser[alice] == 2)
        #expect(byUser[bob] == 1)
    }

    @Test("shares split: remainder goes to largest fractional part, sum preserved")
    func sharesRemainderLargestFraction() throws {
        // 100 split 1:2 -> 33.33... and 66.66...; bob's fraction (0.66) wins the cent.
        let splits = try SplitCalculator.calculate(
            totalAmount: 100,
            currency: "USD",
            participants: [alice, bob],
            splitType: .shares,
            shares: [alice: 1, bob: 2]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "33.33"))
        #expect(byUser[bob] == Decimal(string: "66.67"))
    }

    @Test("shares split: equal fractions tie-break to lowest UUID")
    func sharesTieBreakLowestUUID() throws {
        // 10/3 with equal shares behaves exactly like the equal split.
        let splits = try SplitCalculator.calculate(
            totalAmount: 10,
            currency: "USD",
            participants: [bob, charlie, alice],
            splitType: .shares,
            shares: [alice: 1, bob: 1, charlie: 1]
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == 10)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "3.34"))
        #expect(byUser[bob] == Decimal(string: "3.33"))
        #expect(byUser[charlie] == Decimal(string: "3.33"))
    }

    @Test("shares split: zero-decimal currency stays on whole units")
    func sharesZeroDecimalCurrency() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 100,
            currency: "JPY",
            participants: [alice, bob],
            splitType: .shares,
            shares: [alice: 1, bob: 2]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 33)
        #expect(byUser[bob] == 67)
    }

    @Test("shares split: sum preserved across awkward weights")
    func sharesSumPreserved() throws {
        let dave = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!
        let shares: [UUID: Decimal] = [
            alice: Decimal(string: "1.5")!,
            bob: Decimal(string: "0.5")!,
            charlie: Decimal(string: "2.25")!,
            dave: Decimal(string: "0.75")!,
        ]
        let total = Decimal(string: "97.31")!
        let splits = try SplitCalculator.calculate(
            totalAmount: total,
            currency: "INR",
            participants: [alice, bob, charlie, dave],
            splitType: .shares,
            shares: shares
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == total)
        #expect(splits.allSatisfy { CurrencyCatalog.hasValidPrecision($0.amountOwed, currency: "INR") })
    }

    @Test("shares split: single participant takes the whole total")
    func sharesSingleParticipant() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: Decimal(string: "12.34")!,
            currency: "EUR",
            participants: [alice],
            splitType: .shares,
            shares: [alice: Decimal(string: "0.5")!]
        )
        #expect(splits.count == 1)
        #expect(splits[0].amountOwed == Decimal(string: "12.34"))
    }

    @Test("shares split: missing shares dictionary throws")
    func sharesMissingDictionaryThrows() {
        #expect(throws: SplitCalculatorError.sharesRequired) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .shares
            )
        }
    }

    @Test("shares split: missing participant share throws")
    func sharesMissingParticipantThrows() {
        #expect(throws: SplitCalculatorError.missingShareForParticipant(bob)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .shares,
                shares: [alice: 1]
            )
        }
    }

    @Test("shares split: share for non-participant throws")
    func sharesExtraShareThrows() {
        #expect(throws: SplitCalculatorError.extraShareForNonParticipant(charlie)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .shares,
                shares: [alice: 1, bob: 1, charlie: 1]
            )
        }
    }

    @Test("shares split: zero or negative share throws")
    func sharesNonPositiveThrows() {
        #expect(throws: SplitCalculatorError.nonPositiveShare(alice)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .shares,
                shares: [alice: 0, bob: 1]
            )
        }
        #expect(throws: SplitCalculatorError.nonPositiveShare(bob)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .shares,
                shares: [alice: 1, bob: -1]
            )
        }
    }

    @Test("shares split: duplicate participant throws")
    func sharesDuplicateParticipantThrows() {
        #expect(throws: SplitCalculatorError.duplicateParticipant(alice)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, alice, bob],
                splitType: .shares,
                shares: [alice: 1, bob: 1]
            )
        }
    }

    // MARK: percentage

    @Test("percentage split: whole percentages divide proportionally")
    func percentageWholeProportional() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 80,
            currency: "EUR",
            participants: [alice, bob],
            splitType: .percentage,
            percentages: [alice: 75, bob: 25]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 60)
        #expect(byUser[bob] == 20)
        #expect(splits.allSatisfy { $0.splitType == .percentage })
    }

    @Test("percentage split: carries the percentage on each split")
    func percentageCarriesValues() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 80,
            currency: "EUR",
            participants: [alice, bob],
            splitType: .percentage,
            percentages: [alice: Decimal(string: "12.5")!, bob: Decimal(string: "87.5")!]
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.percentage) })
        #expect(byUser[alice] == Decimal(string: "12.5"))
        #expect(byUser[bob] == Decimal(string: "87.5"))
        #expect(splits.allSatisfy { $0.shareUnits == nil })
    }

    @Test("percentage split: remainder cent lands deterministically, sum preserved")
    func percentageRemainderDeterministic() throws {
        // 100 at 33.33 / 33.33 / 33.34 leaves one cent; the fractional parts
        // are 0.33/0.33/0.34, so charlie (33.34) takes it.
        let splits = try SplitCalculator.calculate(
            totalAmount: 100,
            currency: "USD",
            participants: [alice, bob, charlie],
            splitType: .percentage,
            percentages: [
                alice: Decimal(string: "33.33")!,
                bob: Decimal(string: "33.33")!,
                charlie: Decimal(string: "33.34")!,
            ]
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == 100)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "33.33"))
        #expect(byUser[bob] == Decimal(string: "33.33"))
        #expect(byUser[charlie] == Decimal(string: "33.34"))
    }

    @Test("percentage split: sum must be exactly 100")
    func percentageSumMustBe100() {
        #expect(throws: SplitCalculatorError.percentagesDoNotSumTo100(actual: 99)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .percentage,
                percentages: [alice: 50, bob: 49]
            )
        }
    }

    @Test("percentage split: missing dictionary, missing participant, extras, non-positive throw")
    func percentageValidationThrows() {
        #expect(throws: SplitCalculatorError.percentagesRequired) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100, currency: "EUR", participants: [alice, bob], splitType: .percentage
            )
        }
        #expect(throws: SplitCalculatorError.missingPercentageForParticipant(bob)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100, currency: "EUR", participants: [alice, bob],
                splitType: .percentage, percentages: [alice: 100]
            )
        }
        #expect(throws: SplitCalculatorError.extraPercentageForNonParticipant(charlie)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100, currency: "EUR", participants: [alice, bob],
                splitType: .percentage, percentages: [alice: 50, bob: 50, charlie: 1]
            )
        }
        #expect(throws: SplitCalculatorError.nonPositivePercentage(alice)) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100, currency: "EUR", participants: [alice, bob],
                splitType: .percentage, percentages: [alice: 0, bob: 100]
            )
        }
    }

    @Test("equalPercentages: sums to 100 with leftover basis points to lowest UUIDs")
    func equalPercentagesSeed() {
        let three = SplitCalculator.equalPercentages(participants: [bob, charlie, alice])
        #expect(three[alice] == Decimal(string: "33.34"))
        #expect(three[bob] == Decimal(string: "33.33"))
        #expect(three[charlie] == Decimal(string: "33.33"))
        #expect(three.values.reduce(Decimal(0), +) == 100)

        let two = SplitCalculator.equalPercentages(participants: [alice, bob])
        #expect(two[alice] == 50)
        #expect(two[bob] == 50)

        #expect(SplitCalculator.equalPercentages(participants: []).isEmpty)
    }
}
