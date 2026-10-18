import { expect, test } from "vitest";
import {
  parseSplitwise as parse,
  parseCSVFields,
  parseImportDate,
  parseImportDecimal,
} from "./splitwise-import";
import { realExport } from "./splitwise-fixture";
import { computeBalances } from "./balance-engine";
import { ledgerExpense, ledgerSettlement } from "./test-support";
import { fromMinor } from "./money";
const fixture = () => parse(realExport),
  expense = (name: string) =>
    fixture().expenses.find((e) => e.description === name)!;
test("parsesPeople", () =>
  expect(fixture().people).toEqual([
    "Rithwik Shetty",
    "Lym",
    "Shreya Iyer",
    "Sachin",
    "Sparsh Khandeparker",
    "Esha",
  ]));
test("skipsNonExpenseRows", () => {
  const r = fixture();
  expect(r.expenses).toHaveLength(9);
  expect(r.settlements).toHaveLength(22);
  expect(r.rows.some((e) => e.description === "Total balance")).toBe(false);
});
test("rejectsBadHeader", () => expect(() => parse("a,b,c\n1,2,3")).toThrow());
test("emptyThrows", () =>
  expect(() => parse("")).toThrowError(
    expect.objectContaining({ code: "empty" }),
  ));
test("paymentRowIsSettlement", () =>
  expect(
    fixture().settlements.find((s) => s.description === "Lym paid Sparsh K."),
  ).toMatchObject({ from: "Lym", to: "Sparsh Khandeparker", amount: 1374n }));
test("settleAllIsSettlement", () =>
  expect(
    fixture().settlements.find(
      (s) =>
        s.description === "Settle all balances" &&
        s.amount === 393n &&
        s.from === "Shreya Iyer",
    )?.to,
  ).toBe("Sachin"));
test("singlePayerReconstruction", () => {
  const e = expense("Asda Gnochi night");
  expect(e.total).toBe(1965n);
  expect(e.payments).toEqual([{ person: "Sachin", amount: 1965n }]);
  expect(e.splits).toHaveLength(5);
  expect(e.splits.every((s) => s.amount === 393n)).toBe(true);
  expect(e.splits.some((s) => s.person === "Sparsh Khandeparker")).toBe(false);
});
test("multiPayerReconstruction", () => {
  const e = expense("Peacock drinks");
  expect(e.total).toBe(8640n);
  expect(e.payments).toHaveLength(3);
  expect(e.payments.every((s) => s.amount === 2880n)).toBe(true);
  expect(e.splits).toHaveLength(5);
  expect(e.splits.every((s) => s.amount === 1728n)).toBe(true);
});
test("unequalCentsPreserved", () =>
  expect(
    expense("Paste tax").splits.find((s) => s.person === "Lym")?.amount,
  ).toBe(24n));
test("sumsAreExact", () => {
  for (const e of fixture().expenses) {
    expect(e.payments.reduce((n, p) => n + p.amount, 0n)).toBe(e.total);
    expect(e.splits.reduce((n, p) => n + p.amount, 0n)).toBe(e.total);
    expect(
      [...e.payments, ...e.splits].every((s) => typeof s.amount === "bigint"),
    ).toBe(true);
  }
});
test("noWarnings", () => expect(fixture().warnings).toEqual([]));
test("balancesMatchSplitwise", () => {
  const f = fixture(),
    ids = Object.fromEntries(
      f.people.map((p, i) => [
        p,
        `00000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`,
      ]),
    );
  const expenses = f.expenses.map((e) =>
    ledgerExpense(
      Object.fromEntries(
        e.payments.map((s) => [
          ids[s.person]!,
          fromMinor(s.amount, e.currency),
        ]),
      ),
      Object.fromEntries(
        e.splits.map((s) => [ids[s.person]!, fromMinor(s.amount, e.currency)]),
      ),
      e.currency,
      fromMinor(e.total, e.currency),
    ),
  );
  const settlements = f.settlements.map((s) =>
    ledgerSettlement(
      ids[s.from]!,
      ids[s.to]!,
      fromMinor(s.amount, s.currency),
      s.currency,
    ),
  );
  const balances = computeBalances(expenses, settlements);
  const expected = [576n, -1152n, -576n, 1152n, 0n, 0n];
  for (const [i, name] of f.people.entries())
    expect(
      balances
        .filter((b) => b.forUser === ids[name] && b.currency === "GBP")
        .reduce((n, b) => n + b.amount, 0n),
    ).toBe(expected[i]);
});
test("quotedFields", () => {
  expect(parseCSVFields('a,"b,c",d')).toEqual(["a", "b,c", "d"]);
  expect(parseCSVFields('"a""b",c')).toEqual(['a"b', "c"]);
});
test("dateParsing", () =>
  expect(parseImportDate("2023-03-16")).toBe("2023-03-16T12:00:00.000Z"));
test("duplicateNamesMerge", () => {
  const r = parse(
    "Date,Description,Category,Cost,Currency,Bob,Bob,Carol\n2023-01-01,Lunch,General,30.00,GBP,12.00,8.00,-20.00",
  );
  expect(r.people).toEqual(["Bob", "Carol"]);
  expect(r.warnings.some((w) => w.message.includes("merged"))).toBe(true);
  expect(r.expenses[0]?.payments).toEqual([{ person: "Bob", amount: 3000n }]);
  expect(r.expenses[0]?.splits).toHaveLength(2);
  expect(r.expenses[0]?.splits.reduce((n, s) => n + s.amount, 0n)).toBe(3000n);
  expect(r.expenses[0]?.splits.filter((s) => s.person === "Bob")).toHaveLength(
    1,
  );
});
test("thousandsSeparatorSkipped", () => {
  const r = parse(
    'Date,Description,Category,Cost,Currency,A,B\n2023-01-01,Big,General,"1,234.56",GBP,"617.28","-617.28"',
  );
  expect(r.expenses).toEqual([]);
  expect(r.warnings.some((w) => w.message.includes("Unreadable"))).toBe(true);
});
test("bomHandled", () => {
  const r = parse(
    "\uFEFFDate,Description,Category,Cost,Currency,A,B\n2023-01-01,X,General,10.00,GBP,5.00,-5.00",
  );
  expect(r.people).toEqual(["A", "B"]);
  expect(r.expenses).toHaveLength(1);
});
test("largeAmountNoOverflow", () => {
  const e = parse(
    "Date,Description,Category,Cost,Currency,A,B\n2023-01-01,Yacht,General,100000000.00,GBP,50000000.00,-50000000.00",
  ).expenses[0]!;
  expect(e.payments.reduce((n, p) => n + p.amount, 0n)).toBe(10000000000n);
  expect(e.splits.reduce((n, p) => n + p.amount, 0n)).toBe(10000000000n);
  expect(e.payments).toEqual([{ person: "A", amount: 10000000000n }]);
});
test("unbalancedRowSkipped", () => {
  const r = parse(
    "Date,Description,Category,Cost,Currency,A,B,C\n2023-01-01,Weird,General,10.00,GBP,5.00,5.00,5.00",
  );
  expect(r.expenses).toEqual([]);
  expect(r.warnings.length).toBeGreaterThan(0);
});
test("strict numeric parser rejects partial tokens", () => {
  for (const value of ["", "1,000", "1x", "NaN", "1e2", ".", "--1"])
    expect(parseImportDecimal(value)).toBeNull();
  expect(parseImportDecimal("+1.20")).toBe("1.2");
  expect(parseImportDecimal("-.5")).toBe("-0.5");
});
test("Kotlin BOM duplicate malformed-row fixture", () => {
  const r = parse(
    '\uFEFFDate,Description,Category,Cost,Currency,Alice,Alice\n2026-01-01,Dinner,Food,10.00,GBP,3.00,2.00\nnope,Bad,Food,4.00,GBP,2.00,-2.00\n2026-01-03,Grouped,Food,"1,000.00",GBP,500.00,-500.00',
  );
  expect(r.people).toEqual(["Alice"]);
  expect(r.expenses).toHaveLength(1);
  expect(r.warnings).toHaveLength(4);
});
test("date parser preserves Swift lenient calendar rollover", () =>
  expect(parseImportDate("2026-02-30")).toBe("2026-03-02T12:00:00.000Z"));
test("no people and wrong leading columns have typed errors", () => {
  expect(() => parse("Date,Description,Category,Cost,Currency")).toThrowError(
    expect.objectContaining({ code: "noPeople" }),
  );
  expect(() => parse("When,What,Category,Cost,Currency,Alice")).toThrowError(
    expect.objectContaining({ code: "unexpectedHeader" }),
  );
});
test("arbitrary person names cannot collide with JavaScript object prototypes", () => {
  const r = parse(
    "Date,Description,Category,Cost,Currency,__proto__,constructor\n2026-01-01,Lunch,Food,10,GBP,5,-5",
  );
  expect(r.people).toEqual(["__proto__", "constructor"]);
  expect(r.expenses[0]?.payments).toEqual([
    { person: "__proto__", amount: 1000n },
  ]);
});
test("rounding drift uses the first largest payer on a tie, matching Swift max", () => {
  const result = parse(
    "Date,Description,Category,Cost,Currency,A,B,C\n2026-01-01,Lunch,Food,10,GBP,5.01,5.01,-10",
  );
  expect(result.expenses[0]?.payments).toEqual([
    { person: "A", amount: 499n },
    { person: "B", amount: 501n },
  ]);
  expect(result.expenses[0]?.splits).toEqual([{ person: "C", amount: 1000n }]);
  expect(result.warnings).toEqual([]);
});
