import type { LedgerExpense, LedgerRows } from "./models";
import { ledgerFromRows } from "./models";
import { compare } from "./decimal";
export interface PersonSpend {
  personID: string;
  paid: bigint;
  share: bigint;
}
export interface CategorySpend {
  categoryID: string | null;
  total: bigint;
}
export interface TripSpendSummary {
  currency: string;
  total: bigint;
  perPerson: PersonSpend[];
  perCategory: CategorySpend[];
}
export function summarizeSpend(expenses: readonly LedgerExpense[]): TripSpendSummary[] {
  const currencies = [...new Set(expenses.filter((e) => !e.deletedAt).map((e) => e.amount.currency))].sort();
  return currencies.map((currency) => {
    const group = expenses.filter((e) => !e.deletedAt && e.amount.currency === currency),
      people = new Map<string, PersonSpend>(),
      categories = new Map<string | null, bigint>();
    for (const e of group) {
      for (const p of e.payments) {
        const value = people.get(p.payerID) ?? {
          personID: p.payerID,
          paid: 0n,
          share: 0n,
        };
        value.paid += p.amountPaid;
        people.set(p.payerID, value);
      }
      for (const s of e.splits) {
        const value = people.get(s.participantID) ?? {
          personID: s.participantID,
          paid: 0n,
          share: 0n,
        };
        value.share += s.amountOwed;
        people.set(s.participantID, value);
      }
      categories.set(e.categoryID, (categories.get(e.categoryID) ?? 0n) + e.amount.amount);
    }
    return {
      currency,
      total: group.reduce((n, e) => n + e.amount.amount, 0n),
      perPerson: [...people.values()].sort((a, b) => compare(b.share, a.share) || compare(b.personID, a.personID)),
      perCategory: [...categories]
        .map(([categoryID, total]) => ({ categoryID, total }))
        .sort(
          (a, b) =>
            compare(b.total, a.total) ||
            (a.categoryID === b.categoryID
              ? 0
              : a.categoryID === null
                ? 1
                : b.categoryID === null
                  ? -1
                  : compare(a.categoryID, b.categoryID)),
        ),
    };
  });
}
export function spendFromRows(rows: LedgerRows): TripSpendSummary[] {
  return summarizeSpend(ledgerFromRows(rows).expenses);
}
export const TripAnalytics = { summarize: summarizeSpend };
