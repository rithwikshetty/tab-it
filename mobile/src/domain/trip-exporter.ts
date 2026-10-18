import { timestampUnits } from "./conflict-resolver";
import type { TripRows } from "./models";
import { balancesFromRows } from "./balance-engine";
import { spendFromRows } from "./trip-analytics";
import {
  calendarDay,
  formatClockTime,
  type TimeZoneOffset,
} from "./expense-dates";
import { formatMoney } from "./money-formatter";
import { fromMinor } from "./money";
import { compare, normalizeDecimal, subtractDecimals } from "./decimal";
export interface ExportExpenseRow {
  id: string;
  date: string;
  description: string;
  amount: string;
  currency: string;
  category: string;
  paidBy: string;
  paidByDetail: string;
  splitBetween: string;
  splitDetail: string;
  paymentMethod: string;
  createdBy: string;
  createdAt: string;
  lastEditedBy: string;
  lastEditedAt: string;
}
export interface ExportPaymentRow {
  expenseID: string;
  date: string;
  description: string;
  payerID: string;
  payerName: string;
  currency: string;
  amountPaid: string;
  paymentMode: string;
}
export interface ExportSplitRow {
  expenseID: string;
  date: string;
  description: string;
  participantID: string;
  participantName: string;
  currency: string;
  amountOwed: string;
  splitType: string;
}
export interface ExportSettlementRow {
  date: string;
  from: string;
  to: string;
  amount: string;
  currency: string;
  note: string;
}
export interface ExportSummary {
  totalsByCurrency: {
    currency: string;
    total: string;
  }[];
  personSummaries: {
    name: string;
    currency: string;
    totalPaid: string;
    totalOwed: string;
  }[];
  pairBalances: {
    from: string;
    to: string;
    currency: string;
    amount: string;
  }[];
}
export interface ExportData {
  tripName: string;
  expenses: ExportExpenseRow[];
  expensePayments: ExportPaymentRow[];
  expenseSplits: ExportSplitRow[];
  settlements: ExportSettlementRow[];
  summary: ExportSummary;
}
export type WorkbookCell =
  | {
      type: "string";
      value: string;
    }
  | {
      type: "number";
      value: string;
    };
export interface WorkbookSheet {
  name: string;
  rows: WorkbookCell[][];
}
export interface Workbook {
  sheets: WorkbookSheet[];
}
export function extractExportData(
  rows: TripRows,
  locale = "en-US",
  timeZone: TimeZoneOffset = "UTC",
): ExportData {
  const name = (id: string) =>
      rows.people.find((p) => p.id === id)?.display_name ?? "Unknown",
    userName = (id: string) =>
      rows.people.find((p) => p.user_id === id)?.display_name ??
      id.toUpperCase();
  const personKey = (id: string) =>
    name(id).toLowerCase() + "|" + id.toUpperCase();
  const timestamp = (instant: string) =>
    calendarDay(instant, timeZone) +
    " " +
    formatClockTime(instant, timeZone, "24h");
  const expensePayments: ExportPaymentRow[] = [],
    expenseSplits: ExportSplitRow[] = [];
  const expenses = rows.expenses
    .filter((e) => !e.deleted_at)
    .slice()
    .sort((a, b) => compare(a.expense_date, b.expense_date))
    .map((e) => {
      const payments = rows.payments
          .filter((p) => p.expense_id === e.id)
          .slice()
          .sort((a, b) =>
            compare(personKey(a.trip_person_id), personKey(b.trip_person_id)),
          ),
        splits = rows.splits
          .filter((s) => s.expense_id === e.id)
          .slice()
          .sort((a, b) =>
            compare(personKey(a.trip_person_id), personKey(b.trip_person_id)),
          );
      for (const p of payments)
        expensePayments.push({
          expenseID: e.id.toUpperCase(),
          date: e.expense_date,
          description: e.description,
          payerID: p.trip_person_id.toUpperCase(),
          payerName: name(p.trip_person_id),
          currency: e.currency,
          amountPaid: normalizeDecimal(p.amount_paid),
          paymentMode: p.payment_mode,
        });
      for (const s of splits)
        expenseSplits.push({
          expenseID: e.id.toUpperCase(),
          date: e.expense_date,
          description: e.description,
          participantID: s.trip_person_id.toUpperCase(),
          participantName: name(s.trip_person_id),
          currency: e.currency,
          amountOwed: normalizeDecimal(s.amount_owed),
          splitType: s.split_type,
        });
      return {
        id: e.id.toUpperCase(),
        date: e.expense_date,
        description: e.description,
        amount: normalizeDecimal(e.amount),
        currency: e.currency,
        category:
          rows.categories?.find((c) => c.id === e.category_id)?.name ?? "",
        paidBy: payments.map((p) => name(p.trip_person_id)).join(", "),
        paidByDetail: payments
          .map(
            (p) =>
              `${name(p.trip_person_id)}: ${formatMoney(p.amount_paid, e.currency, locale)}`,
          )
          .join("; "),
        splitBetween: splits.map((s) => name(s.trip_person_id)).join(", "),
        splitDetail: splits
          .map(
            (s) =>
              `${name(s.trip_person_id)}: ${formatMoney(s.amount_owed, e.currency, locale)}`,
          )
          .join("; "),
        paymentMethod: e.payment_method,
        createdBy: userName(e.created_by),
        createdAt: timestamp(e.created_at),
        lastEditedBy: e.last_edited_by ? userName(e.last_edited_by) : "",
        lastEditedAt: e.last_edited_by ? timestamp(e.updated_at) : "",
      };
    });
  const settlements = rows.settlements
    .filter((s) => !s.deleted_at)
    .slice()
    .sort((a, b) =>
      compare(timestampUnits(a.settled_at), timestampUnits(b.settled_at)),
    )
    .map((s) => ({
      date: calendarDay(s.settled_at, timeZone),
      from: name(s.from_person_id),
      to: name(s.to_person_id),
      amount: normalizeDecimal(s.amount),
      currency: s.currency,
      note: s.note ?? "",
    }));
  const summaries = spendFromRows(rows),
    peopleIDs = [
      ...new Set(summaries.flatMap((s) => s.perPerson.map((p) => p.personID))),
    ].sort();
  const personSummaries = peopleIDs.flatMap((id) =>
    summaries.flatMap((s) => {
      const p = s.perPerson.find((p) => p.personID === id);
      return p && (p.paid !== 0n || p.share !== 0n)
        ? [
            {
              name: name(id),
              currency: s.currency,
              totalPaid: fromMinor(p.paid, s.currency),
              totalOwed: fromMinor(p.share, s.currency),
            },
          ]
        : [];
    }),
  );
  const pairBalances = balancesFromRows(rows)
    .filter((b) => b.amount > 0n)
    .map((b) => ({
      from: name(b.withUser),
      to: name(b.forUser),
      currency: b.currency,
      amount: fromMinor(b.amount, b.currency),
    }))
    .sort(
      (a, b) =>
        compare(a.currency, b.currency) ||
        compare(a.from, b.from) ||
        compare(a.to, b.to) ||
        compare(a.amount, b.amount),
    );
  return {
    tripName: rows.trip.name,
    expenses,
    expensePayments,
    expenseSplits,
    settlements,
    summary: {
      totalsByCurrency: summaries.map((s) => ({
        currency: s.currency,
        total: fromMinor(s.total, s.currency),
      })),
      personSummaries,
      pairBalances,
    },
  };
}
const str = (value: string): WorkbookCell => ({ type: "string", value });
const num = (value: string): WorkbookCell => ({
  type: "number",
  value: normalizeDecimal(value),
});
const header = (values: string[]): WorkbookCell[] => values.map(str);
export function buildWorkbook(data: ExportData): Workbook {
  const summary: WorkbookCell[][] = [
    header(["Total Spent per Currency"]),
    header(["Currency", "Total"]),
    ...data.summary.totalsByCurrency.map((t) => [
      str(t.currency),
      num(t.total),
    ]),
    [],
    header(["Per-Person Breakdown"]),
    header(["Person", "Currency", "Total Paid", "Total Owed", "Net"]),
    ...data.summary.personSummaries.map((p) => [
      str(p.name),
      str(p.currency),
      num(p.totalPaid),
      num(p.totalOwed),
      num(subtractDecimals(p.totalPaid, p.totalOwed)),
    ]),
    [],
    header(["Net Balances Between Pairs"]),
    header(["Owes (From)", "Owed To", "Currency", "Amount"]),
    ...data.summary.pairBalances.map((p) => [
      str(p.from),
      str(p.to),
      str(p.currency),
      num(p.amount),
    ]),
  ];
  return {
    sheets: [
      {
        name: "Expenses",
        rows: [
          header([
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
          ]),
          ...data.expenses.map((r) => [
            str(r.id),
            str(r.date),
            str(r.description),
            num(r.amount),
            str(r.currency),
            str(r.category),
            str(r.paidBy),
            str(r.paidByDetail),
            str(r.splitBetween),
            str(r.splitDetail),
            str(r.paymentMethod),
            str(r.createdBy),
            str(r.createdAt),
            str(r.lastEditedBy),
            str(r.lastEditedAt),
          ]),
        ],
      },
      {
        name: "Expense Payments",
        rows: [
          header([
            "Expense ID",
            "Date",
            "Description",
            "Payer ID",
            "Payer Name",
            "Currency",
            "Amount Paid",
            "Payment Mode",
          ]),
          ...data.expensePayments.map((r) => [
            str(r.expenseID),
            str(r.date),
            str(r.description),
            str(r.payerID),
            str(r.payerName),
            str(r.currency),
            num(r.amountPaid),
            str(r.paymentMode),
          ]),
        ],
      },
      {
        name: "Expense Splits",
        rows: [
          header([
            "Expense ID",
            "Date",
            "Description",
            "Participant ID",
            "Participant Name",
            "Currency",
            "Amount Owed",
            "Split Type",
          ]),
          ...data.expenseSplits.map((r) => [
            str(r.expenseID),
            str(r.date),
            str(r.description),
            str(r.participantID),
            str(r.participantName),
            str(r.currency),
            num(r.amountOwed),
            str(r.splitType),
          ]),
        ],
      },
      {
        name: "Settlements",
        rows: [
          header(["Date", "From", "To", "Amount", "Currency", "Note"]),
          ...data.settlements.map((r) => [
            str(r.date),
            str(r.from),
            str(r.to),
            num(r.amount),
            str(r.currency),
            str(r.note),
          ]),
        ],
      },
      { name: "Summary", rows: summary },
    ],
  };
}
export function sheetCSV(sheet: WorkbookSheet): string {
  return (
    sheet.rows
      .map((row) =>
        row
          .map((c) =>
            /[",\r\n]/.test(c.value)
              ? '"' + c.value.replace(/"/g, '""') + '"'
              : c.value,
          )
          .join(","),
      )
      .join("\r\n") + "\r\n"
  );
}
export function exportCSVs(data: ExportData): {
  name: string;
  text: string;
}[] {
  return buildWorkbook(data).sheets.map((s) => ({
    name: s.name + ".csv",
    text: sheetCSV(s),
  }));
}
export function exportText(data: ExportData): string {
  return buildWorkbook(data)
    .sheets.map(
      (s) =>
        s.name +
        "\n" +
        s.rows.map((row) => row.map((c) => c.value).join("\t")).join("\n"),
    )
    .join("\n\n");
}
export const TripExporter = {
  extractData: extractExportData,
  buildWorkbook,
  sheetCSV,
  exportCSVs,
  exportText,
};
