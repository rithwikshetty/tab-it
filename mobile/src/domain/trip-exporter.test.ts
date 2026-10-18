import { expect, test } from "vitest";
import { extractExportData, buildWorkbook, exportCSVs, exportText, sheetCSV, type ExportData } from "./trip-exporter";
import { buildWorkbookXML, workbookXLSX, spreadsheetColumn, xmlDecimal } from "./workbook-xlsx";
import { a, b, c, tripRows, person, addExpense } from "./test-support";
test("extractDataUsesPaymentMethodNotMode", () => {
  const r = addExpense(tripRows("trip", "Tokyo", [person(a, "Alice")]), "expense", { [a]: "60" }, { [a]: "60" }, "60", "EUR", {
      description: "Taxi",
      payment_method: "cash",
    }),
    data = extractExportData(r);
  expect(data.expenses[0]?.paymentMethod).toBe("cash");
  expect(data.expensePayments[0]?.paymentMode).toBe("equal");
});
function data(): ExportData {
  return {
    tripName: "Barcelona",
    expenses: [
      {
        id: "00000000-0000-0000-0000-000000000101",
        date: "2026-05-22",
        description: "Dinner",
        amount: "120",
        currency: "EUR",
        category: "Food",
        paidBy: "Alice, Bob",
        paidByDetail: "Alice: EUR 70.00; Bob: EUR 50.00",
        splitBetween: "Alice, Bob, Cara",
        splitDetail: "Alice: EUR 40.00; Bob: EUR 40.00; Cara: EUR 40.00",
        paymentMethod: "card",
        createdBy: "Alice",
        createdAt: "2026-05-22 20:30",
        lastEditedBy: "Cara",
        lastEditedAt: "2026-05-22 21:00",
      },
    ],
    expensePayments: [
      {
        expenseID: "00000000-0000-0000-0000-000000000101",
        date: "2026-05-22",
        description: "Dinner",
        payerID: a,
        payerName: "Alice",
        currency: "EUR",
        amountPaid: "70",
        paymentMode: "equal",
      },
      {
        expenseID: "00000000-0000-0000-0000-000000000101",
        date: "2026-05-22",
        description: "Dinner",
        payerID: b,
        payerName: "Bob",
        currency: "EUR",
        amountPaid: "50",
        paymentMode: "equal",
      },
    ],
    expenseSplits: [a, b, c].map((id, i) => ({
      expenseID: "00000000-0000-0000-0000-000000000101",
      date: "2026-05-22",
      description: "Dinner",
      participantID: id,
      participantName: ["Alice", "Bob", "Cara"][i]!,
      currency: "EUR",
      amountOwed: "40",
      splitType: "equal",
    })),
    settlements: [],
    summary: {
      totalsByCurrency: [{ currency: "EUR", total: "120" }],
      personSummaries: [],
      pairBalances: [],
    },
  };
}
test("workbookHasNormalizedExpensePaymentAndSplitSheets", () => {
  const w = buildWorkbook(data());
  expect(w.sheets.map((s) => s.name)).toEqual(["Expenses", "Expense Payments", "Expense Splits", "Settlements", "Summary"]);
  const e = w.sheets[0]!.rows.map((r) => r.map((c) => c.value));
  expect(e[0]).toEqual([
    "Expense ID",
    "Date",
    "Description",
    "Amount",
    "Currency",
    "Category",
    "Paid By",
    "Paid By Detail",
    "Split Between",
    "Split Detail",
    "Payment Method",
    "Created By",
    "Created At",
    "Last Edited By",
    "Last Edited At",
  ]);
  expect(e[1]?.slice(6, 10)).toEqual([
    "Alice, Bob",
    "Alice: EUR 70.00; Bob: EUR 50.00",
    "Alice, Bob, Cara",
    "Alice: EUR 40.00; Bob: EUR 40.00; Cara: EUR 40.00",
  ]);
  const p = w.sheets[1]!.rows.map((r) => r.map((c) => c.value));
  expect(p).toHaveLength(3);
  expect(p[0]).toEqual(["Expense ID", "Date", "Description", "Payer ID", "Payer Name", "Currency", "Amount Paid", "Payment Mode"]);
  expect(p[1]?.slice(3, 5)).toEqual([a, "Alice"]);
  const s = w.sheets[2]!.rows.map((r) => r.map((c) => c.value));
  expect(s).toHaveLength(4);
  expect(s[0]).toEqual([
    "Expense ID",
    "Date",
    "Description",
    "Participant ID",
    "Participant Name",
    "Currency",
    "Amount Owed",
    "Split Type",
  ]);
  expect(s[3]?.slice(3, 5)).toEqual([c, "Cara"]);
});
test("extraction sorts names and dates and retains exact creator/editor and symbol details", () => {
  const people = [person(a, "Alice"), person(b, "Bob"), person(c, "Cara")];
  let r = addExpense(
    tripRows("trip", "Barcelona", people),
    "e",
    { [b]: "50", [a]: "70" },
    { [c]: "40", [b]: "40", [a]: "40" },
    "120",
    "EUR",
    { last_edited_by: c, updated_at: "2026-05-22T21:00:00Z" },
  );
  const data = extractExportData(r);
  expect(data.expenses[0]).toMatchObject({
    paidBy: "Alice, Bob",
    paidByDetail: "Alice: €70.00; Bob: €50.00",
    splitBetween: "Alice, Bob, Cara",
    splitDetail: "Alice: €40.00; Bob: €40.00; Cara: €40.00",
    createdBy: "Alice",
    lastEditedBy: "Cara",
    lastEditedAt: "2026-05-22 21:00",
  });
  expect(data.summary.totalsByCurrency).toEqual([{ currency: "EUR", total: "120" }]);
  expect(data.summary.personSummaries).toEqual([
    {
      name: "Alice",
      currency: "EUR",
      totalPaid: "70",
      totalOwed: "40",
    },
    {
      name: "Bob",
      currency: "EUR",
      totalPaid: "50",
      totalOwed: "40",
    },
    {
      name: "Cara",
      currency: "EUR",
      totalPaid: "0",
      totalOwed: "40",
    },
  ]);
  expect(data.summary.pairBalances).toEqual([
    {
      from: "Cara",
      to: "Alice",
      currency: "EUR",
      amount: "30",
    },
    {
      from: "Cara",
      to: "Bob",
      currency: "EUR",
      amount: "10",
    },
  ]);
});
test("CSV has exact RFC4180 escaping, decimals, and CRLF", () =>
  expect(
    sheetCSV({
      name: "example",
      rows: [
        [
          { type: "string", value: "a,b" },
          { type: "string", value: 'a"b' },
          { type: "string", value: "a\nb" },
          { type: "number", value: "12.5" },
        ],
        [],
      ],
    }),
  ).toBe('"a,b","a""b","a\nb",12.5\r\n\r\n'));
test("CSV and text preserve workbook sheet and cell order", () => {
  const d: ExportData = {
    tripName: "Empty",
    expenses: [],
    expensePayments: [],
    expenseSplits: [],
    settlements: [],
    summary: { totalsByCurrency: [], personSummaries: [], pairBalances: [] },
  };
  expect(exportCSVs(d).map((s) => s.name)).toEqual([
    "Expenses.csv",
    "Expense Payments.csv",
    "Expense Splits.csv",
    "Settlements.csv",
    "Summary.csv",
  ]);
  expect(exportCSVs(d)[3]?.text).toBe("Date,From,To,Amount,Currency,Note\r\n");
  expect(exportText(d)).toBe(
    "Expenses\nExpense ID\tDate\tDescription\tAmount\tCurrency\tCategory\tPaid By\tPaid By Detail\tSplit Between\tSplit Detail\tPayment Method\tCreated By\tCreated At\tLast Edited By\tLast Edited At\n\nExpense Payments\nExpense ID\tDate\tDescription\tPayer ID\tPayer Name\tCurrency\tAmount Paid\tPayment Mode\n\nExpense Splits\nExpense ID\tDate\tDescription\tParticipant ID\tParticipant Name\tCurrency\tAmount Owed\tSplit Type\n\nSettlements\nDate\tFrom\tTo\tAmount\tCurrency\tNote\n\nSummary\nTotal Spent per Currency\nCurrency\tTotal\n\nPer-Person Breakdown\nPerson\tCurrency\tTotal Paid\tTotal Owed\tNet\n\nNet Balances Between Pairs\nOwes (From)\tOwed To\tCurrency\tAmount",
  );
});
test("XLSX numeric cells keep exact decimal text and the Swift minimum two digits", () => {
  expect(xmlDecimal("12.5")).toBe("12.50");
  expect(xmlDecimal("1.23456789")).toBe("1.23456789");
  expect(xmlDecimal("999999999999.99")).toBe("999999999999.99");
  expect([0, 25, 26, 51, 52, 701, 702].map(spreadsheetColumn)).toEqual(["A", "Z", "AA", "AZ", "BA", "ZZ", "AAA"]);
  const w = buildWorkbook(data()),
    files = buildWorkbookXML(w);
  expect(files["xl/worksheets/sheet1.xml"]).toContain('<c r="D2"><v>120.00</v></c>');
  expect(files["xl/workbook.xml"]).toContain('name="Expense Payments"');
});
test("XLSX is a complete stored ZIP with each XML part and central directory", () => {
  const w = buildWorkbook(data()),
    bytes = workbookXLSX(w),
    view = new DataView(bytes.buffer),
    files = buildWorkbookXML(w),
    decoder = new TextDecoder();
  let offset = 0,
    count = 0;
  while (view.getUint32(offset, true) === 0x04034b50) {
    const size = view.getUint32(offset + 18, true),
      nameLength = view.getUint16(offset + 26, true),
      extraLength = view.getUint16(offset + 28, true),
      name = decoder.decode(bytes.slice(offset + 30, offset + 30 + nameLength)),
      start = offset + 30 + nameLength + extraLength;
    expect(decoder.decode(bytes.slice(start, start + size))).toBe(files[name]);
    offset = start + size;
    count++;
  }
  expect(count).toBe(Object.keys(files).length);
  expect(view.getUint32(offset, true)).toBe(0x02014b50);
  expect(view.getUint32(bytes.length - 22, true)).toBe(0x06054b50);
  expect(view.getUint16(bytes.length - 12, true)).toBe(count);
});
