import { describe, expect, test } from "vitest";
import { computeBalances, type UserBalance } from "./balance-engine";
import { a, b, c, d, ledgerExpense as e, ledgerSettlement as s } from "./test-support";
import { toMinor } from "./money";
const single = () => e({ [a]: "30" }, { [a]: "15", [b]: "15" });
const multi = () => e({ [a]: "60", [b]: "40" }, { [a]: "20", [b]: "20", [c]: "60" }, "EUR", "100");
const get = (rows: UserBalance[], from: string, to: string, currency = "EUR") =>
  rows.find((r) => r.forUser === from && r.withUser === to && r.currency === currency)?.amount;
describe("Swift BalanceEngineTests", () => {
  test("emptyInput", () => expect(computeBalances([])).toEqual([]));
  test("singleExpenseTwoWay", () => {
    const r = computeBalances([single()]);
    expect(r).toHaveLength(2);
    expect(r[0]?.currency).toBe("EUR");
    expect(get(r, a, b)).toBe(1500n);
    expect(get(r, b, a)).toBe(-1500n);
  });
  test("payerNotInParticipants", () => {
    const r = computeBalances([e({ [a]: "40" }, { [b]: "20", [c]: "20" })]);
    expect(r).toHaveLength(4);
    expect(r.every((b) => b.forUser !== b.withUser)).toBe(true);
    expect(get(r, a, b)).toBe(2000n);
    expect(get(r, a, c)).toBe(2000n);
  });
  test("payerInParticipantsTheirSplitIgnored", () => {
    const r = computeBalances([e({ [a]: "30" }, { [a]: "10", [b]: "10", [c]: "10" })]);
    expect(r).toHaveLength(4);
    expect(get(r, a, b)).toBe(1000n);
    expect(get(r, a, c)).toBe(1000n);
  });
  test("reciprocalExpensesNet", () => {
    const r = computeBalances([single(), e({ [b]: "20" }, { [a]: "10", [b]: "10" })]);
    expect(get(r, a, b)).toBe(500n);
    expect(get(r, b, a)).toBe(-500n);
  });
  test("zeroNetOmitted", () =>
    expect(computeBalances([e({ [a]: "20" }, { [a]: "10", [b]: "10" }), e({ [b]: "20" }, { [a]: "10", [b]: "10" })])).toEqual([]));
  test("multiCurrency", () => {
    const r = computeBalances([single(), e({ [a]: "40" }, { [a]: "20", [b]: "20" }, "USD")]);
    expect(r).toHaveLength(4);
    expect(get(r, a, b)).toBe(1500n);
    expect(get(r, a, b, "USD")).toBe(2000n);
  });
  test("deterministicOutputOrder", () =>
    expect(
      computeBalances([e({ [a]: "90" }, { [a]: "30", [b]: "30", [c]: "30" }), e({ [b]: "20" }, { [a]: "10", [b]: "10" }, "USD")]),
    ).toEqual([
      {
        forUser: a,
        withUser: b,
        currency: "EUR",
        amount: 3000n,
      },
      {
        forUser: b,
        withUser: a,
        currency: "EUR",
        amount: -3000n,
      },
      {
        forUser: a,
        withUser: b,
        currency: "USD",
        amount: -1000n,
      },
      {
        forUser: b,
        withUser: a,
        currency: "USD",
        amount: 1000n,
      },
      {
        forUser: a,
        withUser: c,
        currency: "EUR",
        amount: 3000n,
      },
      {
        forUser: c,
        withUser: a,
        currency: "EUR",
        amount: -3000n,
      },
    ]));
  test("settlementReducesBalance", () => expect(computeBalances([single()], [s(b, a, "15")])).toEqual([]));
  test("partialSettlement", () => expect(get(computeBalances([single()], [s(b, a, "5")]), a, b)).toBe(1000n));
  test("overSettlement", () => {
    const r = computeBalances([single()], [s(b, a, "20")]);
    expect(get(r, a, b)).toBe(-500n);
    expect(get(r, b, a)).toBe(500n);
  });
  test("softDeletedExpenseExcluded", () =>
    expect(
      get(
        computeBalances([
          single(),
          {
            ...e({ [a]: "100" }, { [a]: "50", [b]: "50" }),
            deletedAt: "2026-01-01",
          },
        ]),
        a,
        b,
      ),
    ).toBe(1500n));
  test("softDeletedSettlementExcluded", () =>
    expect(get(computeBalances([single()], [{ ...s(b, a, "15"), deletedAt: "2026-01-01" }]), a, b)).toBe(1500n));
  test("twoPayersEqualSplit", () => {
    const r = computeBalances([e({ [a]: "60", [b]: "40" }, { [a]: "33.33", [b]: "33.33", [c]: "33.34" }, "EUR", "100")]);
    expect(get(r, c, a)).toBe(-2667n);
    expect(get(r, c, b)).toBe(-667n);
    expect(get(r, a, b)).toBeUndefined();
  });
  test("payerWithMixedNet", () => {
    const r = computeBalances([e({ [a]: "30", [b]: "20" }, { [a]: "40", [b]: "10" }, "EUR", "50")]);
    expect(get(r, a, b)).toBe(-1000n);
    expect(get(r, b, a)).toBe(1000n);
  });
  test("twoCreditorsOneDebtor", () => {
    const r = computeBalances([multi()]);
    expect(get(r, c, a)).toBe(-4000n);
    expect(get(r, c, b)).toBe(-2000n);
  });
  test("netZeroUserExcluded", () => {
    const r = computeBalances([e({ [a]: "20", [b]: "10" }, { [a]: "10", [b]: "10", [c]: "10" }, "EUR", "30")]);
    expect(get(r, c, a)).toBe(-1000n);
    expect(get(r, c, b)).toBeUndefined();
    expect(get(r, a, b)).toBeUndefined();
  });
  test("multiPayerSumInvariant", () => {
    const r = computeBalances([e({ [a]: "100", [b]: "50", [c]: "100" }, { [a]: "120", [b]: "80", [c]: "50" }, "EUR", "250")]);
    expect(get(r, a, c)).toBe(-2000n);
    expect(get(r, b, c)).toBe(-3000n);
    expect(get(r, a, b)).toBeUndefined();
  });
  test("settlementAgainstMultiPayer", () => {
    const r = computeBalances([multi()], [s(c, a, "40")]);
    expect(get(r, c, a)).toBeUndefined();
    expect(get(r, c, b)).toBe(-2000n);
  });
  test("multiPayerMultiCurrency", () => {
    const r = computeBalances([{ ...multi(), amount: { amount: 10000n, currency: "USD" } }, e({ [c]: "50" }, { [a]: "25", [c]: "25" })]);
    expect(get(r, c, a, "USD")).toBe(-4000n);
    expect(get(r, a, c)).toBe(-2500n);
  });
  test("multiPayerAcrossExpenses", () => {
    const r = computeBalances([multi(), e({ [c]: "30" }, { [a]: "15", [c]: "15" })]);
    expect(get(r, c, a)).toBe(-2500n);
    expect(get(r, c, b)).toBe(-2000n);
  });
  const repeating = () => e({ [a]: "20", [b]: "10" }, { [c]: "10", [d]: "20" }, "EUR", "30");
  test("multiPayerSharesAreQuantized", () => {
    const r = computeBalances([repeating()]);
    expect(get(r, c, a)).toBe(-667n);
    expect(get(r, c, b)).toBe(-333n);
    expect(get(r, d, a)).toBe(-1333n);
    expect(get(r, d, b)).toBe(-667n);
    expect(r.filter((x) => x.forUser === c).reduce((n, x) => n + x.amount, 0n)).toBe(-1000n);
    expect(r.filter((x) => x.forUser === d).reduce((n, x) => n + x.amount, 0n)).toBe(-2000n);
  });
  test("settlingDisplayedAmountsZeroesBalances", () => {
    const r = computeBalances([repeating()]);
    expect(
      computeBalances(
        [repeating()],
        r
          .filter((b) => b.amount < 0n)
          .map((b) => ({
            fromUserID: b.forUser,
            toUserID: b.withUser,
            currency: b.currency,
            amount: { amount: -b.amount, currency: b.currency },
            deletedAt: null,
          })),
      ),
    ).toEqual([]);
  });
  test("multiPayerZeroDecimalCurrency", () => {
    const r = computeBalances([e({ [a]: "700", [b]: "300" }, { [c]: "451", [d]: "549" }, "JPY", "1000")]);
    expect(r.filter((x) => x.forUser === c).reduce((n, x) => n + x.amount, 0n)).toBe(-451n);
    expect(r.filter((x) => x.forUser === d).reduce((n, x) => n + x.amount, 0n)).toBe(-549n);
    expect(r.every((x) => typeof x.amount === "bigint")).toBe(true);
  });
});
