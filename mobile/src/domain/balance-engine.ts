import type { LedgerExpense, LedgerSettlement, LedgerRows } from "./models";
import { ledgerFromRows } from "./models";
import { allocateMinor, compare } from "./decimal";
export interface UserBalance {
  forUser: string;
  withUser: string;
  currency: string;
  amount: bigint;
}
export interface PairDebt {
  creditor: string;
  debtor: string;
  amount: bigint;
}
export function canonicalPair(
  a: string,
  b: string,
): {
  lo: string;
  hi: string;
} {
  return a < b ? { lo: a, hi: b } : { lo: b, hi: a };
}
export function distributePairs(expense: LedgerExpense): PairDebt[] {
  const nets = new Map<string, bigint>();
  for (const p of expense.payments) nets.set(p.payerID, (nets.get(p.payerID) ?? 0n) + p.amountPaid);
  for (const s of expense.splits) nets.set(s.participantID, (nets.get(s.participantID) ?? 0n) - s.amountOwed);
  const creditors = [...nets].filter(([, n]) => n > 0n).sort(([a], [b]) => compare(a, b));
  const debtors = [...nets].filter(([, n]) => n < 0n).sort(([a], [b]) => compare(a, b));
  if (!creditors.length) return [];
  const ids = creditors.map(([id]) => id),
    weights = Object.fromEntries(creditors.map(([id, n]) => [id, n.toString()]));
  return debtors.flatMap(([debtor, n]) => {
    const amounts = allocateMinor(-n, ids, weights);
    return creditors.flatMap(([creditor]) => (amounts[creditor] === 0n ? [] : [{ creditor, debtor, amount: amounts[creditor]! }]));
  });
}
export function computeBalances(expenses: readonly LedgerExpense[], settlements: readonly LedgerSettlement[] = []): UserBalance[] {
  const canonical = new Map<string, UserBalance>();
  const add = (creditor: string, debtor: string, currency: string, amount: bigint) => {
    const { lo, hi } = canonicalPair(creditor, debtor),
      key = `${lo}|${hi}|${currency}`;
    const signed = debtor === hi ? amount : -amount;
    canonical.set(key, {
      forUser: lo,
      withUser: hi,
      currency,
      amount: (canonical.get(key)?.amount ?? 0n) + signed,
    });
  };
  for (const e of expenses) if (!e.deletedAt) for (const p of distributePairs(e)) add(p.creditor, p.debtor, e.amount.currency, p.amount);
  for (const s of settlements) if (!s.deletedAt) add(s.toUserID, s.fromUserID, s.amount.currency, -s.amount.amount);
  return [...canonical.values()]
    .sort((a, b) => compare(a.forUser, b.forUser) || compare(a.withUser, b.withUser) || compare(a.currency, b.currency))
    .filter((b) => b.amount !== 0n)
    .flatMap((b) => [
      b,
      {
        ...b,
        forUser: b.withUser,
        withUser: b.forUser,
        amount: -b.amount,
      },
    ]);
}
export function balancesFromRows(rows: LedgerRows): UserBalance[] {
  const ledger = ledgerFromRows(rows);
  return computeBalances(ledger.expenses, ledger.settlements);
}
export const BalanceEngine = { compute: computeBalances, distributePairs };
