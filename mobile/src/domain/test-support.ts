import type { LedgerExpense, LedgerSettlement, TripRows } from "./models";
import type {
  Expense,
  ExpensePayment,
  ExpenseSplit,
  TripPerson,
  Settlement,
} from "./records";
import type { UserBalance } from "./balance-engine";
import { toMinor } from "./money";
export const a = "00000000-0000-0000-0000-00000000000a",
  b = "00000000-0000-0000-0000-00000000000b",
  c = "00000000-0000-0000-0000-00000000000c",
  d = "00000000-0000-0000-0000-00000000000d";
export const now = "2026-05-22T20:30:00.000Z";
export function ledgerExpense(
  paid: Record<string, string>,
  owed: Record<string, string>,
  currency = "EUR",
  amount = Object.values(paid).length === 1 ? Object.values(paid)[0]! : "0",
  categoryID: string | null = null,
): LedgerExpense {
  return {
    id: "expense",
    tripID: "trip",
    categoryID,
    amount: { amount: toMinor(amount, currency), currency },
    deletedAt: null,
    payments: Object.entries(paid).map(([payerID, amount]) => ({
      payerID,
      amountPaid: toMinor(amount, currency),
      paymentMode: "exact",
    })),
    splits: Object.entries(owed).map(([participantID, amount]) => ({
      participantID,
      amountOwed: toMinor(amount, currency),
      splitType: "exact",
      shareUnits: null,
      percentage: null,
    })),
  };
}
export function ledgerSettlement(
  fromUserID: string,
  toUserID: string,
  amount: string,
  currency = "EUR",
): LedgerSettlement {
  return {
    fromUserID,
    toUserID,
    amount: { amount: toMinor(amount, currency), currency },
    deletedAt: null,
  };
}
export function mirrored(
  creditor: string,
  debtor: string,
  amount: string,
  currency = "EUR",
): UserBalance[] {
  const value = toMinor(amount, currency);
  return [
    {
      forUser: creditor,
      withUser: debtor,
      amount: value,
      currency,
    },
    {
      forUser: debtor,
      withUser: creditor,
      amount: -value,
      currency,
    },
  ];
}
export function person(
  id: string,
  display_name: string,
  trip_id = "trip",
  user_id: string | null = id,
): TripPerson {
  return {
    id,
    display_name,
    trip_id,
    user_id,
    email: display_name.toLowerCase() + "@x.test",
    joined_at: now,
    removed_at: null,
    created_at: now,
    updated_at: now,
    write_id: id,
    invited_by: a,
  };
}
export function tripRows(
  id = "trip",
  name = "Demo",
  people = [
    person(a, "Alice", id),
    person(b, "Bob", id),
    person(c, "Cara", id),
  ],
): TripRows {
  return {
    trip: {
      id,
      name,
      kind: "trip",
      member_signature: null,
      created_by: a,
      last_activity_at: now,
      created_at: now,
      updated_at: now,
      write_id: a,
      deleted_at: null,
    },
    people,
    expenses: [],
    payments: [],
    splits: [],
    settlements: [],
    categories: [],
  };
}
export function addExpense(
  rows: TripRows,
  id: string,
  paid: Record<string, string>,
  owed: Record<string, string>,
  amount = "30",
  currency = "EUR",
  extra: Partial<Expense> = {},
): TripRows {
  const expense: Expense = {
    id,
    trip_id: rows.trip.id,
    amount,
    currency,
    category_id: null,
    description: "Dinner",
    expense_date: "2026-05-22",
    receipt_storage_path: null,
    payment_method: "card",
    created_by: a,
    last_edited_by: null,
    created_at: now,
    updated_at: now,
    write_id: a,
    deleted_at: null,
    ...extra,
  };
  const payments: ExpensePayment[] = Object.entries(paid).map(
    ([trip_person_id, amount_paid]) => ({
      expense_id: id,
      trip_person_id,
      amount_paid,
      payment_mode: "equal",
      created_at: now,
      updated_at: now,
      write_id: a,
    }),
  );
  const splits: ExpenseSplit[] = Object.entries(owed).map(
    ([trip_person_id, amount_owed]) => ({
      expense_id: id,
      trip_person_id,
      amount_owed,
      split_type: "equal",
      share_units: null,
      percentage: null,
      created_at: now,
      updated_at: now,
      write_id: a,
    }),
  );
  return {
    ...rows,
    expenses: [...rows.expenses, expense],
    payments: [...rows.payments, ...payments],
    splits: [...rows.splits, ...splits],
  };
}
export function rowSettlement(
  rows: TripRows,
  from_person_id: string,
  to_person_id: string,
  amount: string,
  currency = "EUR",
  extra: Partial<Settlement> = {},
): TripRows {
  const s: Settlement = {
    id: "settlement",
    trip_id: rows.trip.id,
    from_person_id,
    to_person_id,
    amount,
    currency,
    note: null,
    settled_at: now,
    created_by: a,
    created_at: now,
    updated_at: now,
    write_id: a,
    deleted_at: null,
    ...extra,
  };
  return { ...rows, settlements: [...rows.settlements, s] };
}
