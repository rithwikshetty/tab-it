import { expect, test } from "vitest";
import { CurrencyDefaults as C } from "./currency-defaults";
import { a, b, tripRows, addExpense, rowSettlement } from "./test-support";
const date = (n: number) => new Date(n * 1000).toISOString();
test("emptyTripUsesSavedCurrencyBeforeRegion", () =>
  expect(C.defaultCurrency([], [], "JPY", "USD")).toBe("JPY"));
test("tripRecentCurrencyBeatsSavedAndRegion", () => {
  let r = addExpense(tripRows(), "1", {}, {}, "10", "USD", {
    created_at: date(1),
    updated_at: date(1),
  });
  r = addExpense(r, "2", {}, {}, "10", "CHF", {
    created_at: date(2),
    updated_at: date(2),
  });
  expect(C.defaultCurrency(r.expenses, [], "JPY", "GBP")).toBe("CHF");
});
test("firstRunFallsBackToINR", () =>
  expect(C.initialCurrency(null, null)).toBe("INR"));
test("firstRunUsesDeviceRegionCurrency", () =>
  expect(C.initialCurrency(null, "GBP")).toBe("GBP"));
test("deletedAndUnsupportedTripCurrenciesAreIgnored", () => {
  let r = addExpense(tripRows(), "1", {}, {}, "10", "USD", {
    created_at: date(1),
    updated_at: date(1),
  });
  r = addExpense(r, "2", {}, {}, "10", "JPY", {
    created_at: date(3),
    updated_at: date(3),
    deleted_at: date(4),
  });
  r = addExpense(r, "3", {}, {}, "10", "XXX", {
    created_at: date(5),
    updated_at: date(5),
  });
  expect(C.defaultCurrency(r.expenses, [], null, "GBP")).toBe("USD");
});
test("settlementsCountAsRecentTripCurrency", () => {
  let r = addExpense(tripRows(), "1", {}, {}, "10", "USD", {
    created_at: date(1),
    updated_at: date(1),
  });
  r = rowSettlement(r, a, b, "10", "AED", {
    created_at: date(4),
    updated_at: date(4),
  });
  expect(C.defaultCurrency(r.expenses, r.settlements, null, "GBP")).toBe("AED");
});
test("rememberedCurrencyIsNormalizedAndUnsupportedValuesAreIgnored", () => {
  let saved = C.remember("usd");
  expect(C.initialCurrency(saved, "GBP")).toBe("USD");
  saved = C.remember("not-a-code", saved);
  expect(C.initialCurrency(saved, "GBP")).toBe("USD");
});
test("recent-currency ties sort by currency code", () => {
  const r = addExpense(
    addExpense(tripRows(), "1", {}, {}, "1", "USD"),
    "2",
    {},
    {},
    "1",
    "EUR",
  );
  expect(C.mostRecentTripCurrency(r.expenses, [])).toBe("EUR");
});
