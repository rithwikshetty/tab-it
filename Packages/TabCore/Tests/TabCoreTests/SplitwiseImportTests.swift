import Foundation
import Testing
@testable import TabCore

@Suite("Splitwise CSV import")
struct SplitwiseImportTests {

    // A faithful copy of a real Splitwise group export, used as the end-to-end
    // fixture. The trailing `Total balance` row is the authority we validate
    // reconstructed balances against.
    static let realExport = """
    Date,Description,Category,Cost,Currency,Rithwik Shetty,Lym,Shreya Iyer,Sachin,Sparsh Khandeparker,Esha

    2023-03-16,Asda Gnochi night,General,19.65,GBP,-3.93,-3.93,-3.93,15.72,0.00,-3.93
    2023-03-16,Settle all balances,General,3.93,GBP,0.00,0.00,3.93,-3.93,0.00,0.00
    2023-04-02,Paste tax,General,1.49,GBP,-0.25,-0.24,-0.25,-0.25,1.24,-0.25
    2023-04-02,Paste,General,85.40,GBP,-12.50,-13.50,-12.95,-17.45,69.90,-13.50
    2023-04-03,Lym paid Sparsh K.,Payment,13.74,GBP,0.00,13.74,0.00,0.00,-13.74,0.00
    2023-04-20,Uber from Notts Edale,Taxi,10.40,GBP,-1.74,-1.73,8.67,-1.73,-1.73,-1.74
    2023-04-20,Ohannes Edale,General,31.50,GBP,-10.50,-10.50,21.00,0.00,0.00,0.00
    2023-04-22,Wingtrapp 16th apr,General,5.50,GBP,0.00,5.50,-5.50,0.00,0.00,0.00
    2023-04-27,Settle all balances,General,12.75,GBP,12.75,0.00,0.00,0.00,-12.75,0.00
    2023-04-27,Settle all balances,General,12.24,GBP,12.24,0.00,-12.24,0.00,0.00,0.00
    2023-04-27,Settle all balances,General,3.93,GBP,3.93,0.00,0.00,-3.93,0.00,0.00
    2023-05-09,Settle all balances,General,1.73,GBP,0.00,0.00,-1.73,1.73,0.00,0.00
    2023-05-09,Settle all balances,General,17.70,GBP,0.00,0.00,0.00,17.70,-17.70,0.00
    2023-05-20,Settle all balances,General,11.47,GBP,0.00,0.00,11.47,0.00,-11.47,0.00
    2023-06-17,Esha paid Shreya I.,Payment,1.74,GBP,0.00,0.00,-1.74,0.00,0.00,1.74
    2023-06-17,Settle all balances,General,13.75,GBP,0.00,0.00,0.00,0.00,-13.75,13.75
    2023-06-17,Settle all balances,General,3.93,GBP,0.00,0.00,0.00,-3.93,0.00,3.93
    2023-07-28,Cab ,Taxi,18.42,GBP,-3.68,-3.68,18.42,-3.69,-3.69,-3.68
    2023-08-12,Settle all balances,General,3.68,GBP,3.68,0.00,-3.68,0.00,0.00,0.00
    2023-08-30,Settle all balances,General,3.68,GBP,0.00,0.00,-3.68,0.00,0.00,3.68
    2023-08-31,Settle all balances,General,3.69,GBP,0.00,0.00,-3.69,3.69,0.00,0.00
    2023-08-31,Settle all balances,General,3.69,GBP,0.00,0.00,-3.69,0.00,3.69,0.00
    2023-08-31,Settle all balances,General,3.93,GBP,0.00,3.93,0.00,-3.93,0.00,0.00
    2023-10-04,Hey chili,General,78.60,GBP,0.00,-17.80,-19.90,-20.10,78.60,-20.80
    2023-10-04,Esha paid Sparsh K.,Payment,20.80,GBP,0.00,0.00,0.00,0.00,-20.80,20.80
    2023-10-04,Settle all balances,General,17.80,GBP,0.00,17.80,0.00,0.00,-17.80,0.00
    2023-10-22,Peacock drinks,Liquor,86.40,GBP,11.52,-17.28,-17.28,11.52,11.52,0.00
    2023-11-23,Settle all balances,General,31.42,GBP,0.00,0.00,31.42,0.00,-31.42,0.00
    2023-12-15,Settle all balances,General,20.10,GBP,0.00,0.00,0.00,20.10,-20.10,0.00
    2024-01-03,Settle all balances,General,10.41,GBP,0.00,10.41,-10.41,0.00,0.00,0.00
    2026-06-06,Lym paid Rithwik S.,Payment,5.76,GBP,-5.76,5.76,0.00,0.00,0.00,0.00

    2026-06-18,Total balance, , ,GBP,5.76,-11.52,-5.76,11.52,0.00,0.00

    """

    // MARK: - Header & structure

    @Test("Parses the header people in order")
    func parsesPeople() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        #expect(result.people == [
            "Rithwik Shetty", "Lym", "Shreya Iyer", "Sachin", "Sparsh Khandeparker", "Esha",
        ])
    }

    @Test("Skips blank lines and the Total balance summary row")
    func skipsNonExpenseRows() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        // 9 real expenses + 22 settlements; the Total balance row is not a row.
        #expect(result.expenses.count == 9)
        #expect(result.settlements.count == 22)
        #expect(!result.rows.contains { row in
            if case let .expense(e) = row { return e.description == "Total balance" }
            if case let .settlement(s) = row { return s.description == "Total balance" }
            return false
        })
    }

    @Test("Rejects a file without the Splitwise header")
    func rejectsBadHeader() {
        #expect(throws: SplitwiseImport.ParseError.self) {
            _ = try SplitwiseImport.parse("a,b,c\n1,2,3")
        }
    }

    @Test("Empty input throws")
    func emptyThrows() {
        #expect(throws: SplitwiseImport.ParseError.empty) {
            _ = try SplitwiseImport.parse("")
        }
    }

    // MARK: - Classification & direction

    @Test("Payment-category rows become settlements with from = payer")
    func paymentRowIsSettlement() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        let lymPaidSparsh = try #require(result.settlements.first { $0.description == "Lym paid Sparsh K." })
        #expect(lymPaidSparsh.from == "Lym")          // positive net column
        #expect(lymPaidSparsh.to == "Sparsh Khandeparker") // negative net column
        #expect(lymPaidSparsh.amount == Decimal(string: "13.74"))
    }

    @Test("Settle all balances rows become settlements with correct direction")
    func settleAllIsSettlement() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        // 2023-03-16 Settle all balances: Shreya +3.93, Sachin -3.93.
        let row = try #require(result.settlements.first {
            $0.description == "Settle all balances" && $0.amount == Decimal(string: "3.93")
                && $0.from == "Shreya Iyer"
        })
        #expect(row.to == "Sachin")
    }

    // MARK: - Reconstruction

    @Test("Single-payer expense reconstructs payer + equal-ish splits")
    func singlePayerReconstruction() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        let asda = try #require(result.expenses.first { $0.description == "Asda Gnochi night" })
        #expect(asda.total == Decimal(string: "19.65"))
        // Sachin fronted the whole bill.
        #expect(asda.payments.count == 1)
        #expect(asda.payments[0].person == "Sachin")
        #expect(asda.payments[0].amount == Decimal(string: "19.65"))
        // Five people owe 3.93 each (Sparsh, net 0, is excluded).
        #expect(asda.splits.count == 5)
        #expect(asda.splits.allSatisfy { $0.amount == Decimal(string: "3.93") })
        #expect(!asda.splits.contains { $0.person == "Sparsh Khandeparker" })
    }

    @Test("Multi-payer expense splits the cost across all payers")
    func multiPayerReconstruction() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        let peacock = try #require(result.expenses.first { $0.description == "Peacock drinks" })
        #expect(peacock.total == Decimal(string: "86.40"))
        // Three payers each fronted 28.80.
        #expect(peacock.payments.count == 3)
        #expect(peacock.payments.allSatisfy { $0.amount == Decimal(string: "28.80") })
        // Five people owe 17.28 each (Esha, net 0, excluded).
        #expect(peacock.splits.count == 5)
        #expect(peacock.splits.allSatisfy { $0.amount == Decimal(string: "17.28") })
    }

    @Test("Unequal source cents are preserved exactly")
    func unequalCentsPreserved() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        let pasteTax = try #require(result.expenses.first { $0.description == "Paste tax" })
        let lym = try #require(pasteTax.splits.first { $0.person == "Lym" })
        #expect(lym.amount == Decimal(string: "0.24"))   // not rounded to 0.25
    }

    // MARK: - Invariants

    @Test("Every expense's payments and splits sum exactly to its total")
    func sumsAreExact() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        for expense in result.expenses {
            let paid = expense.payments.reduce(Decimal(0)) { $0 + $1.amount }
            let owed = expense.splits.reduce(Decimal(0)) { $0 + $1.amount }
            #expect(paid == expense.total, "payments for \(expense.description)")
            #expect(owed == expense.total, "splits for \(expense.description)")
            for share in expense.payments + expense.splits {
                #expect(CurrencyCatalog.hasValidPrecision(share.amount, currency: expense.currency))
            }
        }
    }

    @Test("No warnings for a clean export")
    func noWarnings() throws {
        let result = try SplitwiseImport.parse(Self.realExport)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
    }

    // MARK: - End-to-end balance fidelity (the gold check)

    @Test("Reconstructed balances match Splitwise's Total balance row exactly")
    func balancesMatchSplitwise() throws {
        let result = try SplitwiseImport.parse(Self.realExport)

        let ids = Dictionary(uniqueKeysWithValues: result.people.enumerated().map { index, name in
            (name, UUID(uuidString: "00000000-0000-0000-0000-0000000000" + String(format: "%02d", index + 1))!)
        })
        let tripID = UUID()

        let expenses: [Expense] = result.expenses.map { row in
            Expense(
                tripID: tripID,
                amount: Money(amount: row.total, currency: row.currency),
                expenseDate: row.date,
                payments: row.payments.map { Payment(payerID: ids[$0.person]!, amountPaid: $0.amount, paymentMode: .exact) },
                splits: row.splits.map { ExpenseSplit(participantID: ids[$0.person]!, amountOwed: $0.amount, splitType: .exact) },
                createdBy: tripID,
                createdAt: row.date,
                updatedAt: row.date
            )
        }
        let settlements: [Settlement] = result.settlements.map { row in
            Settlement(
                tripID: tripID,
                fromUserID: ids[row.from]!,
                toUserID: ids[row.to]!,
                amount: Money(amount: row.amount, currency: row.currency),
                settledAt: row.date,
                createdBy: tripID,
                createdAt: row.date,
                updatedAt: row.date
            )
        }

        let balances = BalanceEngine.compute(expenses: expenses, settlements: settlements)

        // Splitwise's final Total balance row.
        let expected: [String: Decimal] = [
            "Rithwik Shetty": Decimal(string: "5.76")!,
            "Lym": Decimal(string: "-11.52")!,
            "Shreya Iyer": Decimal(string: "-5.76")!,
            "Sachin": Decimal(string: "11.52")!,
            "Sparsh Khandeparker": Decimal(0),
            "Esha": Decimal(0),
        ]
        for (name, id) in ids {
            let net = balances
                .filter { $0.forUser == id && $0.currency == "GBP" }
                .reduce(Decimal(0)) { $0 + $1.amount }
            #expect(net == expected[name], "net for \(name) was \(net), expected \(expected[name]!)")
        }
    }

    // MARK: - Tokenizer

    @Test("Quoted fields with commas are parsed as one field")
    func quotedFields() {
        #expect(SplitwiseImport.parseFields("a,\"b,c\",d") == ["a", "b,c", "d"])
        #expect(SplitwiseImport.parseFields("\"a\"\"b\",c") == ["a\"b", "c"])
    }

    @Test("Dates parse to UTC noon")
    func dateParsing() throws {
        let date = try #require(SplitwiseImport.parseDate("2023-03-16"))
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2023 && parts.month == 3 && parts.day == 16 && parts.hour == 12)
    }

    // MARK: - Robustness fixes

    @Test("Duplicate-named columns merge into one person, summing their nets")
    func duplicateNamesMerge() throws {
        let csv = """
        Date,Description,Category,Cost,Currency,Bob,Bob,Carol
        2023-01-01,Lunch,General,30.00,GBP,12.00,8.00,-20.00
        """
        let result = try SplitwiseImport.parse(csv)
        #expect(result.people == ["Bob", "Carol"])               // deduped
        #expect(result.warnings.contains { $0.message.contains("merged") })

        let expense = try #require(result.expenses.first)
        // Bob's two columns merge to net +20 -> one payer share, one split share.
        #expect(expense.payments.count == 1)
        #expect(expense.payments[0].person == "Bob")
        #expect(expense.payments[0].amount == Decimal(string: "30.00"))
        #expect(expense.splits.count == 2)
        #expect(expense.splits.reduce(Decimal(0)) { $0 + $1.amount } == Decimal(string: "30.00"))
        // No duplicate Bob shares.
        #expect(expense.splits.filter { $0.person == "Bob" }.count == 1)
    }

    @Test("Amounts with thousands separators are rejected, not truncated")
    func thousandsSeparatorSkipped() throws {
        let csv = """
        Date,Description,Category,Cost,Currency,A,B
        2023-01-01,Big,General,"1,234.56",GBP,"617.28","-617.28"
        """
        let result = try SplitwiseImport.parse(csv)
        #expect(result.expenses.isEmpty)
        #expect(result.warnings.contains { $0.message.contains("Unreadable") })
    }

    @Test("A leading UTF-8 BOM is stripped by the parser")
    func bomHandled() throws {
        let csv = "\u{FEFF}Date,Description,Category,Cost,Currency,A,B\n2023-01-01,X,General,10.00,GBP,5.00,-5.00"
        let result = try SplitwiseImport.parse(csv)
        #expect(result.people == ["A", "B"])
        #expect(result.expenses.count == 1)
    }

    @Test("A very large expense reconstructs without integer overflow")
    func largeAmountNoOverflow() throws {
        // The payer-share product (payersOwedTotal * net in minor units) would
        // overflow Int64 here; the Decimal proportion must handle it.
        let csv = """
        Date,Description,Category,Cost,Currency,A,B
        2023-01-01,Yacht,General,100000000.00,GBP,50000000.00,-50000000.00
        """
        let result = try SplitwiseImport.parse(csv)
        let expense = try #require(result.expenses.first)
        #expect(expense.payments.reduce(Decimal(0)) { $0 + $1.amount } == Decimal(string: "100000000.00"))
        #expect(expense.splits.reduce(Decimal(0)) { $0 + $1.amount } == Decimal(string: "100000000.00"))
        #expect(expense.payments.count == 1)
        #expect(expense.payments[0].person == "A")
    }

    @Test("An unbalanced row (nets don't sum to zero) is skipped, never emitting a bad expense")
    func unbalancedRowSkipped() throws {
        let csv = """
        Date,Description,Category,Cost,Currency,A,B,C
        2023-01-01,Weird,General,10.00,GBP,5.00,5.00,5.00
        """
        let result = try SplitwiseImport.parse(csv)
        #expect(result.expenses.isEmpty)
        #expect(!result.warnings.isEmpty)
    }
}
