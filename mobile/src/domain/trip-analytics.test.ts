import { expect, test } from "vitest";
import { summarizeSpend } from "./trip-analytics";
import { a, b, c, ledgerExpense as e } from "./test-support";
const food = "00000000-0000-0000-0000-0000000000f0",
  lodging = "00000000-0000-0000-0000-0000000000f1";
test("empty", () => expect(summarizeSpend([])).toEqual([]));
test("singleExpenseTotal", () => {
  const r = summarizeSpend([e({ [a]: "30" }, { [a]: "15", [b]: "15" }, "EUR", "30", food)]);
  expect(r).toHaveLength(1);
  expect(r[0]?.currency).toBe("EUR");
  expect(r[0]?.total).toBe(3000n);
});
test("perPersonPaidAndShare", () => {
  const s = summarizeSpend([e({ [a]: "70", [b]: "50" }, { [a]: "40", [b]: "40", [c]: "40" }, "EUR", "120", food)])[0]!;
  expect(s.perPerson.find((p) => p.personID === a)).toEqual({
    personID: a,
    paid: 7000n,
    share: 4000n,
  });
  expect(s.perPerson.find((p) => p.personID === b)).toEqual({
    personID: b,
    paid: 5000n,
    share: 4000n,
  });
  expect(s.perPerson.find((p) => p.personID === c)).toEqual({
    personID: c,
    paid: 0n,
    share: 4000n,
  });
  expect(s.perPerson.map((p) => p.personID)).toEqual([c, b, a]);
});
test("totalMatchesBothLedgers", () => {
  const s = summarizeSpend([
    e({ [a]: "90" }, { [a]: "30", [b]: "30", [c]: "30" }, "EUR", "90", food),
    e({ [b]: "20", [c]: "30" }, { [b]: "25", [c]: "25" }, "EUR", "50", lodging),
  ])[0]!;
  expect(s.total).toBe(14000n);
  expect(s.perPerson.reduce((n, p) => n + p.paid, 0n)).toBe(14000n);
  expect(s.perPerson.reduce((n, p) => n + p.share, 0n)).toBe(14000n);
});
test("multiCurrencyPartitioned", () => {
  const s = summarizeSpend([
    e({ [a]: "100" }, { [a]: "100" }, "EUR", "100", food),
    e({ [b]: "8000" }, { [b]: "8000" }, "JPY", "8000", lodging),
  ]);
  expect(s.map((s) => s.currency)).toEqual(["EUR", "JPY"]);
  expect(s.map((s) => s.total)).toEqual([10000n, 8000n]);
});
test("perCategoryAggregated", () => {
  const s = summarizeSpend([
    e({ [a]: "40" }, { [a]: "40" }, "EUR", "40", food),
    e({ [a]: "60" }, { [a]: "60" }, "EUR", "60", food),
    e({ [a]: "200" }, { [a]: "200" }, "EUR", "200", lodging),
    e({ [a]: "25" }, { [a]: "25" }, "EUR", "25"),
  ])[0]!;
  expect(s.perCategory).toEqual([
    { categoryID: lodging, total: 20000n },
    { categoryID: food, total: 10000n },
    { categoryID: null, total: 2500n },
  ]);
});
test("perCategoryTieUncategorizedLast", () =>
  expect(
    summarizeSpend([e({ [a]: "50" }, { [a]: "50" }, "EUR", "50"), e({ [a]: "50" }, { [a]: "50" }, "EUR", "50", food)])[0]?.perCategory,
  ).toEqual([
    { categoryID: food, total: 5000n },
    { categoryID: null, total: 5000n },
  ]));
test("softDeletedExcluded", () => {
  const s = summarizeSpend([
    e({ [a]: "40" }, { [a]: "40" }, "EUR", "40", food),
    {
      ...e({ [b]: "999" }, { [b]: "999" }, "EUR", "999", lodging),
      deletedAt: "2026-04-02",
    },
  ])[0]!;
  expect(s.total).toBe(4000n);
  expect(s.perCategory).toEqual([{ categoryID: food, total: 4000n }]);
  expect(s.perPerson.some((p) => p.personID === b)).toBe(false);
});
