import type { UserBalance } from "./balance-engine";
import { compare } from "./decimal";
export interface SimplifiedDebt {
  fromUser: string;
  toUser: string;
  currency: string;
  amount: bigint;
}
export function simplifyDebts(
  balances: readonly UserBalance[],
): SimplifiedDebt[] {
  const currencies = new Map<string, Map<string, bigint>>();
  for (const b of balances)
    if (b.forUser < b.withUser && b.amount !== 0n) {
      const positions = currencies.get(b.currency) ?? new Map<string, bigint>();
      positions.set(b.forUser, (positions.get(b.forUser) ?? 0n) + b.amount);
      positions.set(b.withUser, (positions.get(b.withUser) ?? 0n) - b.amount);
      currencies.set(b.currency, positions);
    }
  const result: SimplifiedDebt[] = [];
  for (const [currency, positions] of [...currencies].sort(([a], [b]) =>
    compare(a, b),
  )) {
    let creditors = [...positions]
      .filter(([, n]) => n > 0n)
      .map(([id, amount]) => ({ id, amount }));
    let debtors = [...positions]
      .filter(([, n]) => n < 0n)
      .map(([id, amount]) => ({ id, amount: -amount }));
    const sort = (
      a: {
        id: string;
        amount: bigint;
      },
      b: {
        id: string;
        amount: bigint;
      },
    ) => compare(b.amount, a.amount) || compare(a.id, b.id);
    while (creditors.length && debtors.length) {
      creditors.sort(sort);
      debtors.sort(sort);
      const c = creditors[0]!,
        d = debtors[0]!,
        amount = c.amount < d.amount ? c.amount : d.amount;
      result.push({
        fromUser: d.id,
        toUser: c.id,
        currency,
        amount,
      });
      c.amount -= amount;
      d.amount -= amount;
      creditors = creditors.filter((p) => p.amount !== 0n);
      debtors = debtors.filter((p) => p.amount !== 0n);
    }
  }
  return result;
}
export function mirroredSimplifiedBalances(
  balances: readonly UserBalance[],
): UserBalance[] {
  return simplifyDebts(balances).flatMap((d) => [
    {
      forUser: d.toUser,
      withUser: d.fromUser,
      currency: d.currency,
      amount: d.amount,
    },
    {
      forUser: d.fromUser,
      withUser: d.toUser,
      currency: d.currency,
      amount: -d.amount,
    },
  ]);
}
export const DebtSimplifier = { simplify: simplifyDebts };
