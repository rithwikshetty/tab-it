import { expect, test } from "vitest";
import { sanitizeAmountInput, sanitizeShareInput, shareString } from "./money";
import {
  convertAmountText,
  formatMoney,
  formatSigned,
  plainAmountString,
} from "./money-formatter";
test("currencySwitchPreservesValue", () =>
  expect(convertAmountText("123.45", "JPY")).toBe("123"));
test("currencySwitchAddsPrecision", () =>
  expect(convertAmountText("123", "USD")).toBe("123.00"));
test("currencySwitchKeepsEmpty", () =>
  expect(convertAmountText("", "JPY")).toBe(""));
test.each([
  ["pasteUSGrouping", "1,234.56", "USD", "1234.56"],
  ["pasteEUGrouping", "1.234,56", "USD", "1234.56"],
  ["pasteMillionsGrouping", "1.234.567", "USD", "1234567"],
  ["zeroDecimalCurrencyTruncates", "123.45", "JPY", "123"],
  ["excessFractionTruncates", "12.3456", "USD", "12.34"],
  ["commaAsDecimal", "12,5", "EUR", "12.5"],
])("%s", (_name, input, currency, expected) =>
  expect(sanitizeAmountInput(input!, currency!)).toBe(expected),
);
test("display uses half-even; sync uses half-away", () => {
  expect(plainAmountString("1.225", "USD")).toBe("1.22");
  expect(plainAmountString("1.235", "USD")).toBe("1.24");
  expect(plainAmountString("-1.225", "USD")).toBe("-1.22");
});
test("symbol-only and code fallback output is exact", () => {
  expect(formatMoney("1234.5", "GBP")).toBe("£1,234.50");
  expect(formatMoney("12.5", "CHF")).toBe("CHF 12.50");
  expect(formatMoney("123", "JPY")).toBe("¥123");
  expect(formatMoney("1.234", "KWD")).toMatch(/1\.234$/);
  expect(formatMoney("12.5", "EUR", "de-DE")).toBe("€12.50");
  expect(formatSigned("-12.5", "GBP")).toBe("-£12.50");
  expect(formatMoney("-12.5", "GBP")).toBe("£-12.50");
});
test("large display retains every digit", () =>
  expect(formatMoney(99999999999999999999n, "USD")).toBe(
    "$999,999,999,999,999,999.99",
  ));
test("share typing always has two decimals", () => {
  expect(sanitizeShareInput("0,555")).toBe("0.55");
  expect(sanitizeShareInput("1.2.3")).toBe("1.2");
  expect(shareString("1.255")).toBe("1.26");
  expect(shareString("2.00")).toBe("2");
});
test("Money overload formats minor units without converting to a floating-point amount", () =>
  expect(formatMoney({ amount: 123450n, currency: "GBP" })).toBe("£1,234.50"));
test("negative display values that round to zero retain the Swift minus sign", () => {
  expect(plainAmountString("-0.005", "USD")).toBe("-0.00");
  expect(formatMoney("-0.001", "GBP")).toBe("£-0.00");
  expect(formatSigned("-0.005", "GBP")).toBe("-£0.00");
  expect(formatMoney("-0.000", "GBP")).toBe("£0.00");
});
