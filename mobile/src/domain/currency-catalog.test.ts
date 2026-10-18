import { expect, test } from "vitest";
import { CurrencyCatalog as C } from "./currency-catalog";
test("defaultCodeIsHardFallbackCurrency", () => {
  expect(C.defaultCode).toBe("INR");
  expect(C.isSupported(C.defaultCode)).toBe(true);
});
test("includesCommonISOCodes", () => {
  expect(C.supported.length).toBeGreaterThan(100);
  for (const code of ["EUR", "usd", "JPY", "KWD"])
    expect(C.isSupported(code)).toBe(true);
});
test("metadata", () => {
  expect(C.metadata("USD")?.symbol).toBeTruthy();
  expect(C.metadata("USD")?.name).toMatch(/dollar/i);
  expect(C.metadata("USD")?.fractionDigits).toBe(2);
  expect(C.metadata("JPY")?.fractionDigits).toBe(0);
  expect(C.metadata("KWD")?.fractionDigits).toBe(3);
});
test("precisionValidation", () => {
  expect(C.hasValidPrecision("10", "JPY")).toBe(true);
  expect(C.hasValidPrecision("10.01", "JPY")).toBe(false);
  expect(C.hasValidPrecision("1.234", "KWD")).toBe(true);
  expect(C.hasValidPrecision("1.2345", "KWD")).toBe(false);
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
    expect(C.normalizedAmount(value!, code!)).toBe(expected);
});
test("displaySymbolsAreUnique", () => {
  const symbols = C.supported.map((c) =>
    c.symbol.normalize("NFKC").toUpperCase(),
  );
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
    expect(C.metadata(code!)?.symbol).toBe(symbol);
  expect(C.metadata("CAD")?.symbol).not.toBe("$");
  expect(C.metadata("AUD")?.symbol).not.toBe("$");
  expect(C.metadata("CAD")?.symbol).not.toBe(C.metadata("AUD")?.symbol);
});
test("search", () => {
  expect(C.search("usd").some((c) => c.code === "USD")).toBe(true);
  expect(C.search("yen").some((c) => c.code === "JPY")).toBe(true);
  expect(C.search("  ")).toEqual(C.supported);
});
