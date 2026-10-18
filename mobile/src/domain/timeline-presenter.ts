import { timestampUnits } from "./conflict-resolver";
import type { LedgerRows } from "./models";
import type { Expense, TripPerson, Category, Settlement } from "./records";
import type {
  ExpenseRowItem,
  SettlementRowItem,
  TimelineDay,
  TimelineItem,
} from "./view-state";
import type { CalendarOptions } from "./expense-dates";
import { calendarDay, dayID, dayLabel, calendarOffset } from "./expense-dates";
import { toMinor } from "./money";
import { abs, compare } from "./decimal";
import { formatMoney } from "./money-formatter";
export function expenseRow(
  expense: Expense,
  rows: Pick<LedgerRows, "payments" | "splits">,
  people: readonly TripPerson[],
  categories: readonly Category[],
  currentPersonID: string,
  locale = "en-US",
): ExpenseRowItem {
  const payments = rows.payments.filter((p) => p.expense_id === expense.id),
    splits = rows.splits.filter((s) => s.expense_id === expense.id),
    firstPayer = [...payments].sort((a, b) =>
      compare(a.trip_person_id, b.trip_person_id),
    )[0]?.trip_person_id;
  const name = (id: string) =>
    people.find((p) => p.id === id)?.display_name ?? "Member";
  const payerName =
    payments.length > 1
      ? `${payments.length} people`
      : firstPayer
        ? firstPayer === currentPersonID
          ? "you"
          : name(firstPayer)
        : "\u2014";
  const share = splits
      .filter((s) => s.trip_person_id === currentPersonID)
      .reduce((n, s) => n + toMinor(s.amount_owed, expense.currency), 0n),
    paid = payments
      .filter((p) => p.trip_person_id === currentPersonID)
      .reduce((n, p) => n + toMinor(p.amount_paid, expense.currency), 0n),
    net = paid - share;
  const category = categories.find((c) => c.id === expense.category_id);
  return {
    id: expense.id,
    categoryID: category?.id ?? expense.category_id,
    icon: category?.icon ?? "tag",
    name: expense.description,
    payerName,
    totalAmount: formatMoney(expense.amount, expense.currency, locale),
    yourShare: formatMoney(share, expense.currency, locale),
    netAmount:
      net === 0n ? null : formatMoney(abs(net), expense.currency, locale),
    balanceSemantic: net > 0n ? "lent" : net < 0n ? "borrowed" : "neutral",
  };
}
export function settlementRow(
  settlement: Settlement,
  people: readonly TripPerson[],
  currentPersonID: string,
  locale = "en-US",
): SettlementRowItem {
  const fromName =
      settlement.from_person_id === currentPersonID
        ? "You"
        : (people.find((p) => p.id === settlement.from_person_id)
            ?.display_name ?? "Member"),
    toName =
      settlement.to_person_id === currentPersonID
        ? "you"
        : (people.find((p) => p.id === settlement.to_person_id)?.display_name ??
          "Member");
  return {
    id: settlement.id,
    fromName,
    toName,
    formattedAmount: formatMoney(
      settlement.amount,
      settlement.currency,
      locale,
    ),
    text: `${fromName} settled with ${toName}`,
  };
}
export function timelineDays(
  rows: LedgerRows,
  people: readonly TripPerson[],
  categories: readonly Category[],
  currentPersonID: string,
  options: CalendarOptions = {},
): TimelineDay[] {
  const { locale = "en-US" } = options;
  const timeZone = calendarOffset(options);
  const all: {
      day: string;
      created: string;
      item: TimelineItem;
    }[] = [],
    totals = new Map<
      string,
      Map<
        string,
        {
          total: bigint;
          share: bigint;
        }
      >
    >();
  for (const e of rows.expenses.filter((e) => !e.deleted_at)) {
    const day = e.expense_date,
      row = expenseRow(e, rows, people, categories, currentPersonID, locale);
    all.push({
      day,
      created: e.created_at,
      item: { type: "expense", id: e.id, expense: row },
    });
    const currencies =
        totals.get(day) ??
        new Map<
          string,
          {
            total: bigint;
            share: bigint;
          }
        >(),
      value = currencies.get(e.currency) ?? { total: 0n, share: 0n };
    value.total += toMinor(e.amount, e.currency);
    value.share += rows.splits
      .filter(
        (s) => s.expense_id === e.id && s.trip_person_id === currentPersonID,
      )
      .reduce((n, s) => n + toMinor(s.amount_owed, e.currency), 0n);
    currencies.set(e.currency, value);
    totals.set(day, currencies);
  }
  for (const s of rows.settlements.filter((s) => !s.deleted_at))
    all.push({
      day: calendarDay(s.settled_at, timeZone),
      created: s.created_at,
      item: {
        type: "settlement",
        id: s.id,
        settlement: settlementRow(s, people, currentPersonID, locale),
      },
    });
  return [...new Set(all.map((a) => a.day))]
    .sort()
    .reverse()
    .map((day) => ({
      id: dayID(day, timeZone),
      dateLabel: dayLabel(day, locale),
      totals: [
        ...(totals.get(day) ??
          new Map<
            string,
            {
              total: bigint;
              share: bigint;
            }
          >()),
      ]
        .sort(([a], [b]) => compare(a, b))
        .map(([currency, amounts]) => ({
          id: currency,
          currency,
          totalSpend: formatMoney(amounts.total, currency, locale),
          yourShare: formatMoney(amounts.share, currency, locale),
        })),
      items: all
        .filter((a) => a.day === day)
        .sort((a, b) =>
          compare(timestampUnits(b.created), timestampUnits(a.created)),
        )
        .map((a) => a.item),
    }));
}
export const TimelinePresenter = { days: timelineDays };
