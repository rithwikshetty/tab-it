import { expect, test } from "vitest";
import { simplifyDebts, type SimplifiedDebt } from "./debt-simplifier";
import { a, b, c, d, mirrored as m } from "./test-support";
import type { UserBalance } from "./balance-engine";
const debt = (fromUser: string, toUser: string, amount: bigint, currency = "EUR"): SimplifiedDebt => ({
  fromUser,
  toUser,
  amount,
  currency,
});
function nets(balances: UserBalance[]) {
  const r: Record<string, bigint> = {};
  for (const x of balances)
    if (x.forUser < x.withUser) {
      r[x.forUser] = (r[x.forUser] ?? 0n) + x.amount;
      r[x.withUser] = (r[x.withUser] ?? 0n) - x.amount;
    }
  return Object.fromEntries(Object.entries(r).filter(([, n]) => n !== 0n));
}
test("chain", () => expect(simplifyDebts([...m(a, b, "10"), ...m(b, c, "10")])).toEqual([debt(c, a, 1000n)]));
test("cycle", () => expect(simplifyDebts([...m(a, b, "10"), ...m(b, c, "10"), ...m(c, a, "10")])).toEqual([]));
test("multiplePositions", () => {
  const rows = [...m(a, c, "50"), ...m(a, d, "10"), ...m(b, d, "40")],
    r = simplifyDebts(rows);
  expect(r).toHaveLength(3);
  expect(
    nets(
      r.flatMap((x) => [
        {
          forUser: x.toUser,
          withUser: x.fromUser,
          amount: x.amount,
          currency: x.currency,
        },
        {
          forUser: x.fromUser,
          withUser: x.toUser,
          amount: -x.amount,
          currency: x.currency,
        },
      ]),
    ),
  ).toEqual(nets(rows));
});
test("currenciesStaySeparate", () =>
  expect(simplifyDebts([...m(a, b, "12"), ...m(b, c, "12"), ...m(d, a, "900", "JPY")])).toEqual([
    debt(c, a, 1200n),
    debt(a, d, 900n, "JPY"),
  ]));
test("pendingPersonIncluded", () => expect(simplifyDebts(m(d, a, "25"))).toEqual([debt(a, d, 2500n)]));
test("decimalValues", () => expect(simplifyDebts([...m(a, b, "10.01"), ...m(b, c, "3.37")])).toEqual([debt(b, a, 664n), debt(c, a, 337n)]));
test("deterministicTies", () => {
  const rows = [...m(a, c, "10"), ...m(b, d, "10")],
    expected = [debt(c, a, 1000n), debt(d, b, 1000n)];
  expect(simplifyDebts(rows)).toEqual(expected);
  expect(simplifyDebts(rows.reverse())).toEqual(expected);
});
