import type {
  Expense,
  ExpensePayment,
  ExpenseSplit,
  Settlement,
  Trip,
  TripPerson,
  Category,
  SplitType,
  UUID,
} from "./records";
import type { Money } from "./money";
import { toMinor } from "./money";
export type PaymentMode = SplitType;
export interface CalculatedSplit {
  participantID: UUID;
  amountOwed: bigint;
  splitType: SplitType;
  shareUnits: string | null;
  percentage: string | null;
}
export interface Payment {
  payerID: UUID;
  amountPaid: bigint;
  paymentMode: SplitType;
}
export interface LedgerExpense {
  id: UUID;
  tripID: UUID;
  amount: Money;
  categoryID: UUID | null;
  payments: readonly Payment[];
  splits: readonly CalculatedSplit[];
  deletedAt: string | null;
}
export interface LedgerSettlement {
  fromUserID: UUID;
  toUserID: UUID;
  amount: Money;
  deletedAt: string | null;
}
export interface LedgerRows {
  expenses: readonly Expense[];
  payments: readonly ExpensePayment[];
  splits: readonly ExpenseSplit[];
  settlements: readonly Settlement[];
}
export interface TripRows extends LedgerRows {
  trip: Trip;
  people: readonly TripPerson[];
  categories?: readonly Category[];
}
export function toLedgerExpense(
  expense: Expense,
  payments: readonly ExpensePayment[],
  splits: readonly ExpenseSplit[],
): LedgerExpense {
  return {
    id: expense.id,
    tripID: expense.trip_id,
    amount: {
      amount: toMinor(expense.amount, expense.currency),
      currency: expense.currency,
    },
    categoryID: expense.category_id,
    deletedAt: expense.deleted_at,
    payments: payments
      .filter((p) => p.expense_id === expense.id)
      .map((p) => ({
        payerID: p.trip_person_id,
        amountPaid: toMinor(p.amount_paid, expense.currency),
        paymentMode: p.payment_mode,
      })),
    splits: splits
      .filter((s) => s.expense_id === expense.id)
      .map((s) => ({
        participantID: s.trip_person_id,
        amountOwed: toMinor(s.amount_owed, expense.currency),
        splitType: s.split_type,
        shareUnits: s.share_units,
        percentage: s.percentage,
      })),
  };
}
export function toLedgerSettlement(s: Settlement): LedgerSettlement {
  return {
    fromUserID: s.from_person_id,
    toUserID: s.to_person_id,
    amount: { amount: toMinor(s.amount, s.currency), currency: s.currency },
    deletedAt: s.deleted_at,
  };
}
export function ledgerFromRows(rows: LedgerRows) {
  return {
    expenses: rows.expenses.map((e) =>
      toLedgerExpense(e, rows.payments, rows.splits),
    ),
    settlements: rows.settlements.map(toLedgerSettlement),
  };
}
export const paymentMethodDisplayName = (method: string): string =>
  method === "cash"
    ? "Cash"
    : method === "bank_transfer"
      ? "Bank transfer"
      : "Card";
export const splitTypes: readonly SplitType[] = [
  "equal",
  "exact",
  "percentage",
  "shares",
  "adjustment",
];
