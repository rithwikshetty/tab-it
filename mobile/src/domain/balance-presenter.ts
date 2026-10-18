import { compareNames } from "./presentation-helpers";
import type { LedgerRows } from "./models";
import type { TripPerson } from "./records";
import type { BalanceSummary, SimplifiedDebtGroup, SettleUpSuggestion } from "./view-state";
import type { UserBalance } from "./balance-engine";
import { balancesFromRows } from "./balance-engine";
import { simplifyDebts } from "./debt-simplifier";
import { abs, compare } from "./decimal";
import { formatMoney } from "./money-formatter";
export function balanceSummaries(
  rows: LedgerRows,
  people: readonly TripPerson[],
  currentPersonID: string,
  locale = "en-US",
): BalanceSummary[] {
  const debts = simplifyDebts(balancesFromRows(rows)).filter((d) => d.fromUser === currentPersonID || d.toUser === currentPersonID);
  const names = new Map(people.map((p) => [p.id, p.display_name]));
  return [...new Set(debts.map((d) => d.currency))].sort().flatMap((currency) => {
    const group = debts.filter((d) => d.currency === currency),
      net = group.reduce((n, d) => n + (d.toUser === currentPersonID ? d.amount : -d.amount), 0n);
    if (net === 0n) return [];
    const details = group
      .map((debt) => {
        const otherID = debt.toUser === currentPersonID ? debt.fromUser : debt.toUser;
        return { debt, otherID, name: names.get(otherID) ?? "Member" };
      })
      .sort((a, b) => compare(b.debt.amount, a.debt.amount) || compareNames(a.name, b.name) || compare(a.otherID, b.otherID))
      .map((c) => ({
        id: c.otherID,
        counterparty: c.debt.toUser === currentPersonID ? `${c.name} owes you` : `You owe ${c.name}`,
        amount: formatMoney(c.debt.amount, currency, locale),
        semantic: c.debt.toUser === currentPersonID ? ("lent" as const) : ("borrowed" as const),
      }));
    return [
      {
        label: net > 0n ? "You're owed" : "You owe",
        amount: formatMoney(abs(net), currency, locale),
        details,
        semantic: net > 0n ? ("lent" as const) : ("borrowed" as const),
      },
    ];
  });
}
export function simplifiedGroups(
  rows: LedgerRows,
  people: readonly TripPerson[],
  currentPersonID: string,
  locale = "en-US",
): SimplifiedDebtGroup[] {
  const debts = simplifyDebts(balancesFromRows(rows)),
    names = new Map(people.map((p) => [p.id, p.display_name]));
  return [...new Set(debts.map((d) => d.currency))].sort().map((currency) => ({
    id: currency,
    currency,
    debts: debts
      .filter((d) => d.currency === currency)
      .map((d) => ({
        id: `${currency}-${d.fromUser.toUpperCase()}-${d.toUser.toUpperCase()}`,
        fromName: d.fromUser === currentPersonID ? "You" : (names.get(d.fromUser) ?? "Member"),
        toName: d.toUser === currentPersonID ? "you" : (names.get(d.toUser) ?? "Member"),
        amount: formatMoney(d.amount, currency, locale),
        semantic: d.toUser === currentPersonID ? "lent" : d.fromUser === currentPersonID ? "borrowed" : "neutral",
        suggestion: {
          fromPersonID: d.fromUser,
          toPersonID: d.toUser,
          amount: d.amount,
          currency,
        },
      })),
  }));
}
export function suggestedPayment(balances: readonly UserBalance[], currentPersonID: string): SettleUpSuggestion | null {
  const debts = simplifyDebts(balances);
  const outgoing = debts.filter((d) => d.fromUser === currentPersonID),
    incoming = debts.filter((d) => d.toUser === currentPersonID);
  const own = outgoing.length > 0;
  const debt = (own ? outgoing : incoming).sort(
    (a, b) =>
      compare(b.amount, a.amount) || compare(a.currency, b.currency) || compare(own ? a.toUser : a.fromUser, own ? b.toUser : b.fromUser),
  )[0];
  return debt
    ? {
        fromPersonID: debt.fromUser,
        toPersonID: debt.toUser,
        amount: debt.amount,
        currency: debt.currency,
      }
    : null;
}
export const BalancePresenter = {
  summaries: balanceSummaries,
  simplifiedGroups,
};
export const SettleUpPresenter = { suggestedPayment };
