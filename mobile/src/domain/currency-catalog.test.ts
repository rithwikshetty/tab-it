import { expect, test } from "vitest";
import {
  currencyMetadata,
  defaultCurrencyCode,
  hasValidPrecision,
  isSupportedCurrency,
  normalizedAmount,
  searchCurrencies,
  supportedCurrencies,
} from "./currency-catalog";
test("defaultCodeIsHardFallbackCurrency", () => {
  expect(defaultCurrencyCode).toBe("INR");
  expect(isSupportedCurrency(defaultCurrencyCode)).toBe(true);
});
test("includesCommonISOCodes", () => {
  expect(supportedCurrencies.length).toBeGreaterThan(100);
  for (const code of ["EUR", "usd", "JPY", "KWD"]) expect(isSupportedCurrency(code)).toBe(true);
});
test("metadata", () => {
  expect(currencyMetadata("USD")?.symbol).toBeTruthy();
  expect(currencyMetadata("USD")?.name).toMatch(/dollar/i);
  expect(currencyMetadata("USD")?.fractionDigits).toBe(2);
  expect(currencyMetadata("JPY")?.fractionDigits).toBe(0);
  expect(currencyMetadata("KWD")?.fractionDigits).toBe(3);
});
test("precisionValidation", () => {
  expect(hasValidPrecision("10", "JPY")).toBe(true);
  expect(hasValidPrecision("10.01", "JPY")).toBe(false);
  expect(hasValidPrecision("1.234", "KWD")).toBe(true);
  expect(hasValidPrecision("1.2345", "KWD")).toBe(false);
});
test("normalizationUsesCurrencyMinorUnits", () => {
  for (const [value, code, expected] of [
    ["0.001", "EUR", "0"],
    ["0.005", "EUR", "0.01"],
    ["0.4", "JPY", "0"],
    ["1.2344", "BHD", "1.234"],
    ["1.2345", "BHD", "1.235"],
    ["-0.005", "EUR", "-0.01"],
  ])
    expect(normalizedAmount(value!, code!)).toBe(expected);
});
test("displaySymbolsAreUnique", () => {
  const symbols = supportedCurrencies.map((c) => c.symbol.normalize("NFKC").toUpperCase());
  expect(new Set(symbols).size).toBe(symbols.length);
});
test("sharedSymbolClaiming", () => {
  for (const [code, symbol] of [
    ["USD", "$"],
    ["GBP", "£"],
    ["JPY", "¥"],
    ["EUR", "€"],
    ["INR", "₹"],
    ["THB", "฿"],
  ])
    expect(currencyMetadata(code!)?.symbol).toBe(symbol);
  expect(currencyMetadata("CAD")?.symbol).not.toBe("$");
  expect(currencyMetadata("AUD")?.symbol).not.toBe("$");
  expect(currencyMetadata("CAD")?.symbol).not.toBe(currencyMetadata("AUD")?.symbol);
});
test("search", () => {
  expect(searchCurrencies("usd").some((c) => c.code === "USD")).toBe(true);
  expect(searchCurrencies("yen").some((c) => c.code === "JPY")).toBe(true);
  expect(searchCurrencies("  ")).toEqual(supportedCurrencies);
});
