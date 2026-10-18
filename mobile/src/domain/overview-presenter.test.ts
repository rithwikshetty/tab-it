import { expect, test } from "vitest";
import { resolveOverview as resolve } from "./overview-presenter";
import { a, b } from "./test-support";
import type { TripSpendSummary } from "./trip-analytics";
const names = (id: string) => (id === b ? "Marco" : "Member"),
  cats = (id: string | null) => (id === "food" ? "Food & Drink" : id === "lodging" ? "Lodging" : "Other");
const show = (summaries: TripSpendSummary[]) => resolve(summaries, a, names, cats);
test("empty", () => {
  const s = show([]);
  expect(s.isEmpty).toBe(true);
  expect(s.currencies).toEqual([]);
});
test("currencyOptions", () => {
  const s = show([
    {
      currency: "EUR",
      total: 10000n,
      perPerson: [],
      perCategory: [],
    },
    {
      currency: "JPY",
      total: 8000n,
      perPerson: [],
      perCategory: [],
    },
  ]);
  expect(s.currencies).toEqual(["EUR", "JPY"]);
  expect(s.pages.map((p) => p.currency)).toEqual(["EUR", "JPY"]);
});
const summary = (): TripSpendSummary => ({
  currency: "EUR",
  total: 20000n,
  perPerson: [
    { personID: a, paid: 15000n, share: 5000n },
    { personID: b, paid: 5000n, share: 15000n },
  ],
  perCategory: [],
});
test("summaryCard", () =>
  expect(show([summary()]).pages[0]).toMatchObject({
    totalSpent: "€200.00",
    youPaid: "€150.00",
    yourShare: "€50.00",
    yourSharePercent: "25% of trip spend",
  }));
test("personRows", () => {
  const s = summary();
  s.perPerson.reverse();
  const p = show([s]).pages[0]!;
  expect(p.people.find((p) => p.id === a)).toMatchObject({
    name: "You",
    isYou: true,
    shareFraction: 0.25,
  });
  expect(p.people.find((p) => p.id === b)).toMatchObject({
    name: "Marco",
    shareFraction: 0.75,
  });
});
test("categoryRows", () => {
  const p = show([
    {
      currency: "EUR",
      total: 25000n,
      perPerson: [],
      perCategory: [
        { categoryID: "lodging", total: 20000n },
        { categoryID: "food", total: 5000n },
      ],
    },
  ]).pages[0]!;
  expect(p.categories.map((c) => c.name)).toEqual(["Lodging", "Food & Drink"]);
  expect(p.categories[0]?.percent).toBe(0.8);
  expect(p.categories[0]?.fraction).toBe(1);
  expect(p.categories[1]?.fraction).toBe(0.25);
});
test("zero total has no percentage and no invalid chart ratios", () => {
  const p = show([
    {
      currency: "EUR",
      total: 0n,
      perPerson: [{ personID: a, paid: 0n, share: 0n }],
      perCategory: [{ categoryID: null, total: 0n }],
    },
  ]).pages[0]!;
  expect(p.yourSharePercent).toBeNull();
  expect(p.people[0]?.shareFraction).toBe(0);
  expect(p.categories[0]?.fraction).toBe(0);
});
test("non-terminating chart ratios are converted only after exact division", () => {
  const page = show([
    {
      currency: "EUR",
      total: 900n,
      perPerson: [{ personID: a, paid: 0n, share: 700n }],
      perCategory: [],
    },
  ]).pages[0]!;
  expect(page.people[0]?.shareFraction).toBe(7 / 9);
});
