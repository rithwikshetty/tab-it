export type BalanceSemantic = "lent" | "borrowed" | "neutral";
export interface SettleUpSuggestion {
  fromPersonID: string;
  toPersonID: string;
  amount: bigint;
  currency: string;
}
export interface BalanceDetailItem {
  id: string;
  counterparty: string;
  amount: string;
  semantic: BalanceSemantic;
}
export interface BalanceSummary {
  label: string;
  amount: string;
  details: BalanceDetailItem[];
  semantic: BalanceSemantic;
}
export interface SimplifiedDebtRowItem {
  id: string;
  fromName: string;
  toName: string;
  amount: string;
  semantic: BalanceSemantic;
  suggestion: SettleUpSuggestion;
}
export interface SimplifiedDebtGroup {
  id: string;
  currency: string;
  debts: SimplifiedDebtRowItem[];
}
export interface ExpenseRowItem {
  id: string;
  categoryID: string | null;
  icon: string;
  name: string;
  payerName: string;
  totalAmount: string;
  yourShare: string;
  netAmount: string | null;
  balanceSemantic: BalanceSemantic;
  sourceName?: string;
}
export interface SettlementRowItem {
  id: string;
  fromName: string;
  toName: string;
  formattedAmount: string;
  text: string;
  sourceName?: string;
}
export type TimelineItem =
  | {
      type: "expense";
      id: string;
      expense: ExpenseRowItem;
    }
  | {
      type: "settlement";
      id: string;
      settlement: SettlementRowItem;
    };
export interface TimelineDayTotal {
  id: string;
  currency: string;
  totalSpend: string;
  yourShare: string;
}
export interface TimelineDay {
  id: string;
  dateLabel: string;
  totals: TimelineDayTotal[];
  items: TimelineItem[];
}
