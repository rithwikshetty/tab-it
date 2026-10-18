import { expect, test } from "vitest";
import { aggregateBalances as agg, balanceBreakdown as breakdown, ClaimIdentity as I, identityKey } from "./overall-balance-aggregator";
import { a, b, c, mirrored as m } from "./test-support";
const A = I.user(a),
  B = I.user(b),
  C = I.user(c);
const map = {
  a1: A,
  b1: B,
  c1: C,
  a2: A,
  b2: B,
  a3: A,
  b3: B,
  c3: C,
};
const container = (containerID: string, balances: ReturnType<typeof m>) => ({
  containerID,
  balances,
});
const pair = (id = "1", amount = "15", currency = "EUR") => container(id, m("a1", "b1", amount, currency));
const mine = (rows: ReturnType<typeof agg>) => rows.filter((r) => identityKey(r.forIdentity) === identityKey(A));
test("empty", () => expect(agg([], {})).toEqual([]));
test("singlePair", () => {
  const r = agg([pair()], map);
  expect(r).toHaveLength(2);
  expect(mine(r)[0]).toEqual({
    forIdentity: A,
    withIdentity: B,
    currency: "EUR",
    amount: 1500n,
  });
  expect(r.find((r) => identityKey(r.forIdentity) === identityKey(B))?.amount).toBe(-1500n);
});
test("noDoubleCount", () => expect(mine(agg([pair()], map))[0]?.amount).toBe(1500n));
test("collapseAcrossContainers", () => {
  const r = agg([pair("1", "20", "GBP"), container("2", m("b2", "a2", "5", "GBP"))], map);
  expect(r).toHaveLength(2);
  expect(mine(r)[0]?.amount).toBe(1500n);
});
test("multiCurrency", () => {
  const r = agg([container("1", [...m("a1", "b1", "20", "GBP"), ...m("a1", "b1", "10", "EUR")])], map);
  expect(r).toHaveLength(4);
  expect(mine(r).map((r) => [r.currency, r.amount])).toEqual([
    ["EUR", 1000n],
    ["GBP", 2000n],
  ]);
});
test("zeroNets", () => expect(agg([pair("1", "10", "GBP"), container("2", m("b2", "a2", "10", "GBP"))], map)).toEqual([]));
test("claimContinuity", () => {
  const rows = [container("3", m("a3", "b3", "10", "GBP")), pair("1", "5", "GBP")],
    pre = agg(rows, { ...map, b3: I.email("bob@x.com") });
  expect(mine(pre)).toHaveLength(2);
  const post = mine(agg(rows, map));
  expect(post).toHaveLength(1);
  expect(post[0]?.amount).toBe(1500n);
});
test("unmappedSkipped", () => expect(agg([pair()], { a1: A })).toEqual([]));
test("threePersonPlusTrip", () => {
  const r = mine(
    agg([container("3", [...m("a3", "b3", "10", "GBP"), ...m("a3", "c3", "10", "GBP")]), container("1", m("b1", "a1", "4", "GBP"))], map),
  );
  expect(r.find((r) => identityKey(r.withIdentity) === identityKey(B))?.amount).toBe(600n);
  expect(r.find((r) => identityKey(r.withIdentity) === identityKey(C))?.amount).toBe(1000n);
  expect(
    agg([pair()], map).some((r) => identityKey(r.forIdentity) === identityKey(B) && identityKey(r.withIdentity) === identityKey(C)),
  ).toBe(false);
});
test("breakdownPerSource", () => {
  const r = breakdown(
    [pair("1", "20", "GBP"), container("2", m("a2", "b2", "15", "EUR")), container("3", m("b3", "a3", "8", "GBP"))],
    map,
    A,
    B,
  );
  expect(r).toEqual([
    { containerID: "1", currency: "GBP", amount: 2000n },
    { containerID: "2", currency: "EUR", amount: 1500n },
    { containerID: "3", currency: "GBP", amount: -800n },
  ]);
});
test("breakdownExcludesUnrelated", () =>
  expect(breakdown([pair("1", "20", "GBP"), container("2", m("a2", "c1", "5", "GBP"))], map, A, B)).toEqual([
    { containerID: "1", currency: "GBP", amount: 2000n },
  ]));
test("identity resolution normalizes email without trimming and prefers user", () => {
  expect(I.resolve(null, "BOB@x.com")).toEqual(I.email("bob@x.com"));
  expect(I.resolve(a, "bob@x.com")).toEqual(A);
  expect(agg([pair()], { a1: A, b1: A })).toEqual([]);
  expect(breakdown([pair()], map, A, A)).toEqual([]);
});
