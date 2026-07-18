import Foundation
import TabCore

enum TripExporter {

    struct ExportData: Sendable {
        let tripName: String
        let expenses: [ExpenseRow]
        let expensePayments: [ExpensePaymentRow]
        let expenseSplits: [ExpenseSplitRow]
        let settlements: [SettlementRow]
        let summary: Summary
    }

    struct ExpenseRow: Sendable {
        let id: String
        let date: String
        let description: String
        let amount: Decimal
        let currency: String
        let category: String
        let paidBy: String
        let paidByDetail: String
        let splitBetween: String
        let splitDetail: String
        let paymentMethod: String
        let createdBy: String
        let createdAt: String
        let lastEditedBy: String
        let lastEditedAt: String
    }

    struct ExpensePaymentRow: Sendable {
        let expenseID: String
        let date: String
        let description: String
        let payerID: String
        let payerName: String
        let currency: String
        let amountPaid: Decimal
        let paymentMode: String
    }

    struct ExpenseSplitRow: Sendable {
        let expenseID: String
        let date: String
        let description: String
        let participantID: String
        let participantName: String
        let currency: String
        let amountOwed: Decimal
        let splitType: String
    }

    struct SettlementRow: Sendable {
        let date: String
        let from: String
        let to: String
        let amount: Decimal
        let currency: String
        let note: String
    }

    struct CurrencyTotal: Sendable {
        let currency: String
        let total: Decimal
    }

    struct Summary: Sendable {
        let totalsByCurrency: [CurrencyTotal]
        let personSummaries: [PersonSummary]
        let pairBalances: [PairBalance]
    }

    struct PersonSummary: Sendable {
        let name: String
        let currency: String
        let totalPaid: Decimal
        let totalOwed: Decimal
    }

    struct PairBalance: Sendable {
        let from: String
        let to: String
        let currency: String
        let amount: Decimal
    }

    struct Workbook: Sendable {
        let sheets: [WorkbookSheet]
    }

    struct WorkbookSheet: Sendable {
        let name: String
        let rows: [[WorkbookCell]]
    }

    enum WorkbookCell: Sendable, Equatable {
        case string(String)
        case number(Decimal)
    }

    // MARK: - Data extraction

    @MainActor
    static func extractData(
        trip: TripEntity,
        categories: [UUID: CategoryEntity],
        peopleByID: [UUID: TripPersonEntity]
    ) -> ExportData {
        let settlementDateFormatter = DateFormatter()
        settlementDateFormatter.dateFormat = "yyyy-MM-dd"
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let activeExpenses = trip.expenses
            .filter { $0.deletedAt == nil }
            .sorted { $0.expenseDate < $1.expenseDate }

        var expensePaymentRows: [ExpensePaymentRow] = []
        var expenseSplitRows: [ExpenseSplitRow] = []

        let expenseRows: [ExpenseRow] = activeExpenses.map { expense in
            let sortedPayments = expense.payments.sorted {
                personSortKey($0.tripPersonID, peopleByID: peopleByID)
                    < personSortKey($1.tripPersonID, peopleByID: peopleByID)
            }
            let sortedSplits = expense.splits.sorted {
                personSortKey($0.tripPersonID, peopleByID: peopleByID)
                    < personSortKey($1.tripPersonID, peopleByID: peopleByID)
            }

            let paidByNames = sortedPayments.map { personName($0.tripPersonID, peopleByID: peopleByID) }
            let paidByDetails = sortedPayments.map { payment in
                "\(personName(payment.tripPersonID, peopleByID: peopleByID)): \(formatMoney(payment.amountPaid, currency: expense.currency))"
            }
            let splitNames = sortedSplits.map { personName($0.tripPersonID, peopleByID: peopleByID) }
            let splitDetails = sortedSplits.map { split in
                "\(personName(split.tripPersonID, peopleByID: peopleByID)): \(formatMoney(split.amountOwed, currency: expense.currency))"
            }

            for payment in sortedPayments {
                expensePaymentRows.append(ExpensePaymentRow(
                    expenseID: expense.id.uuidString,
                    date: ExpenseDates.serialized(expense.expenseDate),
                    description: expense.descriptionText,
                    payerID: payment.tripPersonID.uuidString,
                    payerName: personName(payment.tripPersonID, peopleByID: peopleByID),
                    currency: expense.currency,
                    amountPaid: payment.amountPaid,
                    paymentMode: payment.paymentModeRaw
                ))
            }

            for split in sortedSplits {
                expenseSplitRows.append(ExpenseSplitRow(
                    expenseID: expense.id.uuidString,
                    date: ExpenseDates.serialized(expense.expenseDate),
                    description: expense.descriptionText,
                    participantID: split.tripPersonID.uuidString,
                    participantName: personName(split.tripPersonID, peopleByID: peopleByID),
                    currency: expense.currency,
                    amountOwed: split.amountOwed,
                    splitType: split.splitTypeRaw
                ))
            }

            let categoryName = expense.categoryID
                .flatMap { categories[$0]?.name } ?? ""

            let createdByName = peopleByID.values
                .first(where: { $0.userID == expense.createdByID })?.displayName
                ?? expense.createdByID.uuidString

            let lastEditedByName: String
            if let editorID = expense.lastEditedByID {
                lastEditedByName = peopleByID.values
                    .first(where: { $0.userID == editorID })?.displayName
                    ?? editorID.uuidString
            } else {
                lastEditedByName = ""
            }

            return ExpenseRow(
                id: expense.id.uuidString,
                date: ExpenseDates.serialized(expense.expenseDate),
                description: expense.descriptionText,
                amount: expense.amount,
                currency: expense.currency,
                category: categoryName,
                paidBy: paidByNames.joined(separator: ", "),
                paidByDetail: paidByDetails.joined(separator: "; "),
                splitBetween: splitNames.joined(separator: ", "),
                splitDetail: splitDetails.joined(separator: "; "),
                paymentMethod: expense.paymentMethodRaw,
                createdBy: createdByName,
                createdAt: timestampFormatter.string(from: expense.createdAt),
                lastEditedBy: lastEditedByName,
                lastEditedAt: expense.lastEditedByID != nil
                    ? timestampFormatter.string(from: expense.updatedAt)
                    : ""
            )
        }

        let activeSettlements = trip.settlements
            .filter { $0.deletedAt == nil }
            .sorted { $0.settledAt < $1.settledAt }

        let settlementRows: [SettlementRow] = activeSettlements.map { settlement in
            let fromName = peopleByID[settlement.fromPersonID]?.displayName ?? "Unknown"
            let toName = peopleByID[settlement.toPersonID]?.displayName ?? "Unknown"
            return SettlementRow(
                date: settlementDateFormatter.string(from: settlement.settledAt),
                from: fromName,
                to: toName,
                amount: settlement.amount,
                currency: settlement.currency,
                note: settlement.note ?? ""
            )
        }

        let coreExpenses = activeExpenses.map { $0.toCoreExpense() }
        let coreSettlements = activeSettlements.map { $0.toCoreSettlement() }

        // Totals by currency
        var currencyTotals: [String: Decimal] = [:]
        for expense in activeExpenses {
            currencyTotals[expense.currency, default: 0] += expense.amount
        }
        let totalsByCurrency = currencyTotals
            .sorted { $0.key < $1.key }
            .map { CurrencyTotal(currency: $0.key, total: $0.value) }

        // Per-person paid and owed
        var personPaid: [UUID: [String: Decimal]] = [:]
        var personOwed: [UUID: [String: Decimal]] = [:]
        for expense in activeExpenses {
            for payment in expense.payments {
                personPaid[payment.tripPersonID, default: [:]][expense.currency, default: 0] += payment.amountPaid
            }
            for split in expense.splits {
                personOwed[split.tripPersonID, default: [:]][expense.currency, default: 0] += split.amountOwed
            }
        }

        let allPersonIDs = Set(personPaid.keys).union(personOwed.keys)
        let allCurrencies = Set(currencyTotals.keys).sorted()

        var personSummaries: [PersonSummary] = []
        for personID in allPersonIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let name = peopleByID[personID]?.displayName ?? "Unknown"
            for currency in allCurrencies {
                let paid = personPaid[personID]?[currency] ?? 0
                let owed = personOwed[personID]?[currency] ?? 0
                if paid != 0 || owed != 0 {
                    personSummaries.append(PersonSummary(
                        name: name,
                        currency: currency,
                        totalPaid: paid,
                        totalOwed: owed
                    ))
                }
            }
        }

        // Net balances between pairs
        let balances = BalanceEngine.compute(expenses: coreExpenses, settlements: coreSettlements)
        var seenPairs: Set<String> = []
        var pairBalances: [PairBalance] = []
        for balance in balances where balance.amount > 0 {
            let pairKey = ([balance.forUser.uuidString, balance.withUser.uuidString].sorted() + [balance.currency])
                .joined(separator: "-")
            guard !seenPairs.contains(pairKey) else { continue }
            seenPairs.insert(pairKey)
            let fromName = peopleByID[balance.withUser]?.displayName ?? "Unknown"
            let toName = peopleByID[balance.forUser]?.displayName ?? "Unknown"
            pairBalances.append(PairBalance(
                from: fromName,
                to: toName,
                currency: balance.currency,
                amount: balance.amount
            ))
        }
        pairBalances.sort {
            ($0.currency, $0.from, $0.to, $0.amount.description)
                < ($1.currency, $1.from, $1.to, $1.amount.description)
        }

        let summary = Summary(
            totalsByCurrency: totalsByCurrency,
            personSummaries: personSummaries,
            pairBalances: pairBalances
        )

        return ExportData(
            tripName: trip.name,
            expenses: expenseRows,
            expensePayments: expensePaymentRows,
            expenseSplits: expenseSplitRows,
            settlements: settlementRows,
            summary: summary
        )
    }

    // MARK: - XLSX generation

    static func generateXLSX(from data: ExportData) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xlsxDir = tempDir.appendingPathComponent("xlsx", isDirectory: true)
        try FileManager.default.createDirectory(
            at: xlsxDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: xlsxDir.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: xlsxDir.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)

        let workbook = buildWorkbook(from: data)
        let sharedStrings = SharedStringTable()
        let sheets = workbook.sheets.map { sheet in
            SheetBuilder(rows: sheet.rows, strings: sharedStrings)
        }

        try writeContentTypes(sheetCount: sheets.count, to: xlsxDir)
        try writeRels(to: xlsxDir)
        try writeWorkbook(sheets: workbook.sheets, to: xlsxDir)
        try writeWorkbookRels(sheetCount: sheets.count, to: xlsxDir)
        try writeStyles(to: xlsxDir)
        try sharedStrings.write(to: xlsxDir)
        for (index, sheet) in sheets.enumerated() {
            try sheet.write(to: xlsxDir.appendingPathComponent("xl/worksheets/sheet\(index + 1).xml"))
        }

        let sanitizedName = data.tripName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outputURL = tempDir.appendingPathComponent("\(sanitizedName) Expenses.xlsx")
        try XLSXArchiveWriter.writeDirectoryContents(from: xlsxDir, to: outputURL)

        let documentsDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let finalURL = documentsDir.appendingPathComponent("\(sanitizedName) Expenses.xlsx")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.copyItem(at: outputURL, to: finalURL)

        return finalURL
    }

    // MARK: - Workbook builders

    static func buildWorkbook(from data: ExportData) -> Workbook {
        Workbook(sheets: [
            WorkbookSheet(name: "Expenses", rows: buildExpensesRows(data.expenses)),
            WorkbookSheet(name: "Expense Payments", rows: buildExpensePaymentRows(data.expensePayments)),
            WorkbookSheet(name: "Expense Splits", rows: buildExpenseSplitRows(data.expenseSplits)),
            WorkbookSheet(name: "Settlements", rows: buildSettlementRows(data.settlements)),
            WorkbookSheet(name: "Summary", rows: buildSummaryRows(data.summary)),
        ])
    }

    private static func buildExpensesRows(_ rows: [ExpenseRow]) -> [[WorkbookCell]] {
        var sheetRows: [[WorkbookCell]] = [[
            .string("Expense ID"), .string("Date"), .string("Description"), .string("Amount"),
            .string("Currency"), .string("Category"), .string("Paid By"), .string("Paid By Detail"),
            .string("Split Between"), .string("Split Detail"), .string("Payment Method"),
            .string("Created By"), .string("Created At"), .string("Last Edited By"), .string("Last Edited At"),
        ]]
        sheetRows += rows.map { row in
            [
                .string(row.id), .string(row.date), .string(row.description), .number(row.amount),
                .string(row.currency), .string(row.category), .string(row.paidBy), .string(row.paidByDetail),
                .string(row.splitBetween), .string(row.splitDetail), .string(row.paymentMethod),
                .string(row.createdBy), .string(row.createdAt), .string(row.lastEditedBy), .string(row.lastEditedAt),
            ]
        }
        return sheetRows
    }

    private static func buildExpensePaymentRows(_ rows: [ExpensePaymentRow]) -> [[WorkbookCell]] {
        var sheetRows: [[WorkbookCell]] = [[
            .string("Expense ID"), .string("Date"), .string("Description"), .string("Payer ID"),
            .string("Payer Name"), .string("Currency"), .string("Amount Paid"), .string("Payment Mode"),
        ]]
        sheetRows += rows.map { row in
            [
                .string(row.expenseID), .string(row.date), .string(row.description), .string(row.payerID),
                .string(row.payerName), .string(row.currency), .number(row.amountPaid), .string(row.paymentMode),
            ]
        }
        return sheetRows
    }

    private static func buildExpenseSplitRows(_ rows: [ExpenseSplitRow]) -> [[WorkbookCell]] {
        var sheetRows: [[WorkbookCell]] = [[
            .string("Expense ID"), .string("Date"), .string("Description"), .string("Participant ID"),
            .string("Participant Name"), .string("Currency"), .string("Amount Owed"), .string("Split Type"),
        ]]
        sheetRows += rows.map { row in
            [
                .string(row.expenseID), .string(row.date), .string(row.description), .string(row.participantID),
                .string(row.participantName), .string(row.currency), .number(row.amountOwed), .string(row.splitType),
            ]
        }
        return sheetRows
    }

    private static func buildSettlementRows(_ rows: [SettlementRow]) -> [[WorkbookCell]] {
        var sheetRows: [[WorkbookCell]] = [[
            .string("Date"), .string("From"), .string("To"), .string("Amount"), .string("Currency"), .string("Note"),
        ]]
        sheetRows += rows.map { row in
            [.string(row.date), .string(row.from), .string(row.to), .number(row.amount), .string(row.currency), .string(row.note)]
        }
        return sheetRows
    }

    private static func buildSummaryRows(_ summary: Summary) -> [[WorkbookCell]] {
        var rows: [[WorkbookCell]] = []
        rows.append([.string("Total Spent per Currency")])
        rows.append([.string("Currency"), .string("Total")])
        rows += summary.totalsByCurrency.map { [.string($0.currency), .number($0.total)] }

        rows.append([])
        rows.append([.string("Per-Person Breakdown")])
        rows.append([.string("Person"), .string("Currency"), .string("Total Paid"), .string("Total Owed"), .string("Net")])
        rows += summary.personSummaries.map { person in
            [
                .string(person.name),
                .string(person.currency),
                .number(person.totalPaid),
                .number(person.totalOwed),
                .number(person.totalPaid - person.totalOwed),
            ]
        }

        rows.append([])
        rows.append([.string("Net Balances Between Pairs")])
        rows.append([.string("Owes (From)"), .string("Owed To"), .string("Currency"), .string("Amount")])
        rows += summary.pairBalances.map { [.string($0.from), .string($0.to), .string($0.currency), .number($0.amount)] }
        return rows
    }

    // MARK: - XLSX XML files

    private static func writeContentTypes(sheetCount: Int, to dir: URL) throws {
        let sheetOverrides = (1...sheetCount)
            .map { "  <Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }
            .joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        \(sheetOverrides)
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        </Types>
        """
        try xml.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    }

    private static func writeRels(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try xml.write(to: dir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
    }

    private static func writeWorkbook(sheets: [WorkbookSheet], to dir: URL) throws {
        let sheetXML = sheets.enumerated()
            .map { index, sheet in
                "    <sheet name=\"\(xmlEscape(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
            }
            .joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
        \(sheetXML)
          </sheets>
        </workbook>
        """
        try xml.write(to: dir.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
    }

    private static func writeWorkbookRels(sheetCount: Int, to dir: URL) throws {
        let worksheetRels = (1...sheetCount)
            .map { "  <Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>" }
            .joined(separator: "\n")
        let styleID = sheetCount + 1
        let sharedStringsID = sheetCount + 2
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(worksheetRels)
          <Relationship Id="rId\(styleID)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId\(sharedStringsID)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
        </Relationships>
        """
        try xml.write(to: dir.appendingPathComponent("xl/_rels/workbook.xml.rels"), atomically: true, encoding: .utf8)
    }

    private static func writeStyles(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="2">
            <font><sz val="11"/><name val="Calibri"/></font>
            <font><b/><sz val="11"/><name val="Calibri"/></font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border><left/><right/><top/><bottom/><diagonal/></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          </cellXfs>
        </styleSheet>
        """
        try xml.write(to: dir.appendingPathComponent("xl/styles.xml"), atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func formatMoney(_ value: Decimal, currency: String) -> String {
        MoneyFormatter.format(value, currency: currency)
    }

    private static func personName(_ id: UUID, peopleByID: [UUID: TripPersonEntity]) -> String {
        peopleByID[id]?.displayName ?? "Unknown"
    }

    private static func personSortKey(_ id: UUID, peopleByID: [UUID: TripPersonEntity]) -> String {
        "\(personName(id, peopleByID: peopleByID).localizedLowercase)|\(id.uuidString)"
    }

    private static func xmlEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - XLSX Archive Writer

private enum XLSXArchiveWriter {
    private static let minimumDOSDate = UInt16(33)

    static func writeDirectoryContents(from sourceDir: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        let basePath = sourceDir.standardizedFileURL.path
        let files = try enumerator.compactMap { item -> ArchiveEntry? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }

            let path = url.standardizedFileURL.path
            let relativeStart = path.index(path.startIndex, offsetBy: basePath.count)
            var relativePath = String(path[relativeStart...])
            if relativePath.hasPrefix("/") {
                relativePath.removeFirst()
            }
            return ArchiveEntry(path: relativePath, url: url)
        }
        .sorted { $0.path < $1.path }

        var archive = Data()
        var centralDirectory = Data()

        for file in files {
            let localHeaderOffset = archive.count
            let fileData = try Data(contentsOf: file.url)
            let pathData = Data(file.path.utf8)
            let crc = CRC32.checksum(fileData)
            try validateZIPLimits(
                pathDataCount: pathData.count,
                fileDataCount: fileData.count,
                localHeaderOffset: localHeaderOffset
            )

            appendLocalFileHeader(
                to: &archive,
                pathData: pathData,
                crc: crc,
                fileSize: UInt32(fileData.count)
            )
            archive.append(fileData)

            appendCentralDirectoryHeader(
                to: &centralDirectory,
                pathData: pathData,
                crc: crc,
                fileSize: UInt32(fileData.count),
                localHeaderOffset: UInt32(localHeaderOffset)
            )
        }

        let centralDirectoryOffset = archive.count
        try validateZIPLimits(
            entryCount: files.count,
            centralDirectorySize: centralDirectory.count,
            centralDirectoryOffset: centralDirectoryOffset
        )

        archive.append(centralDirectory)
        appendEndOfCentralDirectory(
            to: &archive,
            entryCount: UInt16(files.count),
            centralDirectorySize: UInt32(centralDirectory.count),
            centralDirectoryOffset: UInt32(centralDirectoryOffset)
        )

        try archive.write(to: outputURL, options: .atomic)
    }

    private static func appendLocalFileHeader(
        to data: inout Data,
        pathData: Data,
        crc: UInt32,
        fileSize: UInt32
    ) {
        data.appendLittleEndian(UInt32(0x0403_4B50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(minimumDOSDate)
        data.appendLittleEndian(crc)
        data.appendLittleEndian(fileSize)
        data.appendLittleEndian(fileSize)
        data.appendLittleEndian(UInt16(pathData.count))
        data.appendLittleEndian(UInt16(0))
        data.append(pathData)
    }

    private static func appendCentralDirectoryHeader(
        to data: inout Data,
        pathData: Data,
        crc: UInt32,
        fileSize: UInt32,
        localHeaderOffset: UInt32
    ) {
        data.appendLittleEndian(UInt32(0x0201_4B50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(minimumDOSDate)
        data.appendLittleEndian(crc)
        data.appendLittleEndian(fileSize)
        data.appendLittleEndian(fileSize)
        data.appendLittleEndian(UInt16(pathData.count))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(localHeaderOffset)
        data.append(pathData)
    }

    private static func appendEndOfCentralDirectory(
        to data: inout Data,
        entryCount: UInt16,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32
    ) {
        data.appendLittleEndian(UInt32(0x0605_4B50))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(entryCount)
        data.appendLittleEndian(entryCount)
        data.appendLittleEndian(centralDirectorySize)
        data.appendLittleEndian(centralDirectoryOffset)
        data.appendLittleEndian(UInt16(0))
    }

    private static func validateZIPLimits(
        pathDataCount: Int,
        fileDataCount: Int,
        localHeaderOffset: Int
    ) throws {
        guard pathDataCount <= Int(UInt16.max),
              fileDataCount <= Int(UInt32.max),
              localHeaderOffset <= Int(UInt32.max)
        else {
            throw XLSXArchiveError.archiveTooLarge
        }
    }

    private static func validateZIPLimits(
        entryCount: Int,
        centralDirectorySize: Int,
        centralDirectoryOffset: Int
    ) throws {
        guard entryCount <= Int(UInt16.max),
              centralDirectorySize <= Int(UInt32.max),
              centralDirectoryOffset <= Int(UInt32.max)
        else {
            throw XLSXArchiveError.archiveTooLarge
        }
    }

    private struct ArchiveEntry {
        let path: String
        let url: URL
    }

    private enum XLSXArchiveError: Error {
        case archiveTooLarge
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { byte in
        var crc = UInt32(byte)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xEDB8_8320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(contentsOf: buffer)
        }
    }
}

// MARK: - Shared String Table

private final class SharedStringTable: @unchecked Sendable {
    private var strings: [String] = []
    private var lookup: [String: Int] = [:]

    func index(for value: String) -> Int {
        if let existing = lookup[value] { return existing }
        let idx = strings.count
        strings.append(value)
        lookup[value] = idx
        return idx
    }

    func write(to dir: URL) throws {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">
        """
        for str in strings {
            xml += "<si><t>\(xmlEscape(str))</t></si>"
        }
        xml += "</sst>"
        try xml.write(to: dir.appendingPathComponent("xl/sharedStrings.xml"), atomically: true, encoding: .utf8)
    }

    private func xmlEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Sheet Builder

private final class SheetBuilder: @unchecked Sendable {
    private enum XLSXCell {
        case sharedString(Int)
        case number(Decimal)
    }

    private var rows: [[XLSXCell]] = []

    init(rows: [[TripExporter.WorkbookCell]], strings: SharedStringTable) {
        self.rows = rows.map { row in
            row.map { cell in
                switch cell {
                case .string(let value):
                    .sharedString(strings.index(for: value))
                case .number(let value):
                    .number(value)
                }
            }
        }
    }

    func write(to url: URL) throws {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        """

        for (rowIdx, row) in rows.enumerated() {
            let rowNum = rowIdx + 1
            xml += "<row r=\"\(rowNum)\">"
            for (colIdx, cell) in row.enumerated() {
                let colRef = columnLetter(colIdx)
                let cellRef = "\(colRef)\(rowNum)"
                switch cell {
                case .sharedString(let idx):
                    xml += "<c r=\"\(cellRef)\" t=\"s\"><v>\(idx)</v></c>"
                case .number(let value):
                    let formatted = formatDecimalForXML(value)
                    xml += "<c r=\"\(cellRef)\"><v>\(formatted)</v></c>"
                }
            }
            xml += "</row>"
        }

        xml += "</sheetData></worksheet>"
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func columnLetter(_ index: Int) -> String {
        var result = ""
        var n = index
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    // One formatter for the whole workbook — building one per numeric cell adds
    // seconds to large exports.
    private static let xmlDecimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter
    }()

    private func formatDecimalForXML(_ value: Decimal) -> String {
        Self.xmlDecimalFormatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}
