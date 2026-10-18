import { expect, test } from "vitest";
import {
  balanceSummaries,
  simplifiedGroups,
  suggestedPayment,
} from "./balance-presenter";
import { balancesFromRows } from "./balance-engine";
import {
  a,
  b,
  c,
  d,
  tripRows,
  person,
  addExpense,
  rowSettlement,
  mirrored,
} from "./test-support";
const people = [person(a, "You"), person(b, "Sam"), person(c, "Alex")];
test("tiedDetailRowsSortByDisplayName", () => {
  const r = addExpense(
    tripRows("trip", "Demo", people),
    "1",
    { [a]: "90" },
    { [a]: "30", [b]: "30", [c]: "30" },
    "90",
    "GBP",
  );
  const s = balanceSummaries(r, people, a)[0]!;
  expect(s.details.map((d) => d.counterparty)).toEqual([
    "Alex owes you",
    "Sam owes you",
  ]);
  expect(s.details.map((d) => d.amount)).toEqual(["£30.00", "£30.00"]);
  expect(s.semantic).toBe("lent");
});
test("summaryDetailsUseSimplifiedDebts", () => {
  const r = addExpense(
    addExpense(
      tripRows("trip", "Demo", people),
      "1",
      { [b]: "30" },
      { [a]: "30" },
      "30",
      "GBP",
    ),
    "2",
    { [c]: "30" },
    { [b]: "30" },
    "30",
    "GBP",
  );
  const s = balanceSummaries(r, people, a)[0]!;
  expect(s.label).toBe("You owe");
  expect(s.amount).toBe("£30.00");
  expect(s.semantic).toBe("borrowed");
  expect(s.details.map((d) => d.counterparty)).toEqual(["You owe Alex"]);
  expect(s.details.map((d) => d.semantic)).toEqual(["borrowed"]);
});
test("simplifiedTripWideDebts", () => {
  const people = [
      person(a, "You"),
      person(b, "Sam"),
      person(d, "Priya", "trip", null),
    ],
    r = addExpense(
      tripRows("trip", "Demo", people),
      "1",
      { [d]: "90" },
      { [b]: "90" },
      "90",
      "GBP",
    );
  const debt = simplifiedGroups(r, people, a)[0]!.debts[0]!;
  expect(debt.fromName).toBe("Sam");
  expect(debt.toName).toBe("Priya");
  expect(debt.semantic).toBe("neutral");
  expect(debt.suggestion).toEqual({
    fromPersonID: b,
    toPersonID: d,
    amount: 9000n,
    currency: "GBP",
  });
});
test("suggestsLargestDebtorToCurrentUser", () => {
  let r = tripRows();
  for (let i = 0; i < 6; i++)
    r = addExpense(
      r,
      String(i),
      { [a]: "120" },
      { [a]: "40", [b]: "40", [c]: "40" },
      "120",
    );
  r = rowSettlement(rowSettlement(r, b, a, "210"), c, a, "70");
  expect(suggestedPayment(balancesFromRows(r), a)).toEqual({
    fromPersonID: c,
    toPersonID: a,
    amount: 17000n,
    currency: "EUR",
  });
});
test("suggestsRedirectedTripWideBalance", () => {
  const r = addExpense(
    addExpense(
      tripRows(),
      "1",
      { [a]: "300" },
      { [a]: "150", [c]: "150" },
      "300",
    ),
    "2",
    { [b]: "30" },
    { [a]: "15", [b]: "15" },
  );
  expect(suggestedPayment(balancesFromRows(r), a)).toEqual({
    fromPersonID: c,
    toPersonID: a,
    amount: 13500n,
    currency: "EUR",
  });
});
test("suggestsCrossSettledRedirect", () =>
  expect(
    suggestedPayment([...mirrored(b, a, "10"), ...mirrored(c, b, "10")], a),
  ).toEqual({
    fromPersonID: a,
    toPersonID: c,
    amount: 1000n,
    currency: "EUR",
  }));
