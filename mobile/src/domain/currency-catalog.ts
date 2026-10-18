import { currencyData } from "./currency-data";
import { decimalRational, roundDivide, scaledString } from "./decimal";
export interface CurrencyMetadata {
  code: string;
  symbol: string;
  name: string;
  fractionDigits: number;
}
export const defaultCurrencyCode = "INR";
export const maximumSupportedFractionDigits = 8;
export const supportedCurrencies: readonly CurrencyMetadata[] = currencyData;
export const supportedCurrencyCodes = supportedCurrencies.map((c) => c.code);
const byCode = new Map(supportedCurrencies.map((c) => [c.code, c]));
export function normalizedCode(code: string): string {
  return code.trim().toUpperCase();
}
export function isSupportedCurrency(code: string): boolean {
  return byCode.has(normalizedCode(code));
}
export function currencyMetadata(code: string): CurrencyMetadata | undefined {
  return byCode.get(normalizedCode(code));
}
export function displayMetadata(code: string): CurrencyMetadata {
  const normalized = normalizedCode(code);
  return (
    currencyMetadata(normalized) ?? {
      code: normalized,
      symbol: normalized,
      name: normalized,
      fractionDigits: 2,
    }
  );
}
export function fractionDigits(currency: string): number {
  return displayMetadata(currency).fractionDigits;
}
export function minorUnitMultiplier(currency: string): bigint {
  return 10n ** BigInt(fractionDigits(currency));
}
export function hasValidPrecision(amount: string, currency: string): boolean {
  const r = decimalRational(amount);
  return (r.numerator * minorUnitMultiplier(currency)) % r.denominator === 0n;
}
export function normalizedAmount(amount: string, currency: string): string {
  const r = decimalRational(amount);
  return scaledString(
    roundDivide(r.numerator * minorUnitMultiplier(currency), r.denominator),
    fractionDigits(currency),
  );
}
const fold = (s: string) =>
  s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
export function searchCurrencies(query: string): readonly CurrencyMetadata[] {
  const q = fold(query.trim());
  return q
    ? supportedCurrencies.filter((c) =>
        [c.code, c.symbol, c.name].some((s) => fold(s).includes(q)),
      )
    : supportedCurrencies;
}
export const CurrencyCatalog = {
  defaultCode: defaultCurrencyCode,
  maximumSupportedFractionDigits,
  supported: supportedCurrencies,
  supportedCodes: supportedCurrencyCodes,
  normalizedCode,
  isSupported: isSupportedCurrency,
  metadata: currencyMetadata,
  displayMetadata,
  fractionDigits,
  minorUnitMultiplier,
  hasValidPrecision,
  normalizedAmount,
  search: searchCurrencies,
};
