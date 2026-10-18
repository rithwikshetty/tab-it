import { expect, test } from "vitest";
import { parseMoney, toMinor, fromMinor, parseAmountInput, addMoney, decimalFromInput } from "./money";
test("moneyBasics", () => {
  const money = parseMoney("10", "EUR");
  expect(money).toEqual(parseMoney("10", "EUR"));
  expect(money).not.toEqual(parseMoney("10", "USD"));
});
test.each([
  ["12.50", "USD", 1250n, "12.5"],
  ["1000", "JPY", 1000n, "1000"],
  ["1.2345", "KWD", 1235n, "1.235"],
  ["-0.005", "USD", -1n, "-0.01"],
  ["999999999999.99999999", "USD", 100000000000000n, "1000000000000"],
  ["-0.00000001", "USD", 0n, "0"],
])("normalizes pulled %s %s", (input, currency, minor, expected) => {
  expect(toMinor(input as string, currency as string)).toBe(minor);
  expect(fromMinor(minor as bigint, currency as string)).toBe(expected);
});
test("typed amount is sanitized before parsing", () => {
  expect(parseAmountInput("1.234,56", "EUR")).toBe(123456n);
  expect(parseAmountInput("", "EUR")).toBeNull();
});
test("Kotlin addsExactDecimalAmountsInTheSameCurrency", () =>
  expect(addMoney(parseMoney("0.10", "GBP"), parseMoney("0.20", "GBP"))).toEqual({ amount: 30n, currency: "GBP" }));
test("Kotlin refusesToMixCurrencies", () =>
  expect(() => addMoney(parseMoney("10", "GBP"), parseMoney("10", "EUR"))).toThrow("Cannot add different currencies."));
test("Kotlin Money parse normalizes and validates currency code shape", () => {
  expect(parseMoney("1", " gbp ").currency).toBe("GBP");
  expect(() => parseMoney("1", "Pounds")).toThrow();
});
test("Swift Decimal input accepts numeric prefixes and exponents", () => {
  expect(decimalFromInput("1e2")).toBe("100");
  expect(decimalFromInput("1e")).toBe("1");
  expect(decimalFromInput("1.2x")).toBe("1.2");
  expect(decimalFromInput("١٢.٥")).toBeNull();
});
