import { expect, test } from "vitest";
import { timelineDays } from "./timeline-presenter";
import { a, b, tripRows, addExpense, rowSettlement } from "./test-support";
test("sharesAndDailyTotals", () => {
  let r = addExpense(tripRows(), "borrowed", { [b]: "100" }, { [a]: "40", [b]: "60" }, "100", "THB", {
    expense_date: "2026-07-10",
    created_at: "2026-07-10T12:00:01Z",
  });
  r = addExpense(r, "lent", { [a]: "50" }, { [a]: "20", [b]: "30" }, "50", "THB", {
    expense_date: "2026-07-10",
    created_at: "2026-07-10T12:00:02Z",
  });
  r = addExpense(r, "zero", { [b]: "10" }, { [b]: "10" }, "10", "USD", {
    expense_date: "2026-07-10",
    created_at: "2026-07-10T12:00:03Z",
  });
  r = rowSettlement(r, a, b, "999", "THB", {
    settled_at: "2026-07-10T12:00:00Z",
    created_at: "2026-07-10T12:00:04Z",
  });
  const day = timelineDays(r, [], [], a)[0]!;
  expect(day.totals).toEqual([
    {
      id: "THB",
      currency: "THB",
      totalSpend: "฿150.00",
      yourShare: "฿60.00",
    },
    {
      id: "USD",
      currency: "USD",
      totalSpend: "$10.00",
      yourShare: "$0.00",
    },
  ]);
  const rows = day.items.flatMap((i) => (i.type === "expense" ? [i.expense] : []));
  expect(rows.find((r) => r.id === "lent")).toMatchObject({
    yourShare: "฿20.00",
    totalAmount: "฿50.00",
    netAmount: "฿30.00",
    balanceSemantic: "lent",
  });
  expect(rows.find((r) => r.id === "borrowed")).toMatchObject({
    yourShare: "฿40.00",
    netAmount: "฿40.00",
    balanceSemantic: "borrowed",
  });
  expect(rows.find((r) => r.id === "zero")).toMatchObject({
    yourShare: "$0.00",
    totalAmount: "$10.00",
    balanceSemantic: "neutral",
    netAmount: null,
  });
  expect(day.items.map((i) => i.id)).toEqual(["settlement", "zero", "lent", "borrowed"]);
});
test("expenseRowsUseStoredCalendarDay", () => {
  const r = addExpense(tripRows(), "1", { [a]: "10" }, { [a]: "5", [b]: "5" }, "10", "EUR", { expense_date: "2026-06-10" });
  expect(timelineDays(r, [], [], a, { utcOffsetMinutes: 840 })[0]?.dateLabel).toBe("Jun 10");
});
test("settlement grouping uses the local instant", () => {
  const r = rowSettlement(tripRows(), a, b, "1", "EUR", {
    settled_at: "2026-06-10T23:00:00Z",
  });
  expect(timelineDays(r, [], [], a, { utcOffsetMinutes: 840 })[0]?.dateLabel).toBe("Jun 11");
});
