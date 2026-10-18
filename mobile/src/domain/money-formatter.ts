import { displayMetadata, fractionDigits, minorUnitMultiplier } from "./currency-catalog";
import { abs, decimalRational, roundDivide, scaledString } from "./decimal";
import { decimalFromInput, sanitizeAmountInput, sanitizeShareInput, shareString, type Money } from "./money";
function displayMinor(amount: string | bigint, currency: string): bigint {
  if (typeof amount === "bigint") return amount;
  const r = decimalRational(amount);
  return roundDivide(r.numerator * minorUnitMultiplier(currency), r.denominator, "halfEven");
}
function isNegativeAmount(amount: string | bigint): boolean {
  return typeof amount === "bigint" ? amount < 0n : decimalRational(amount).numerator < 0n;
}
export function plainAmountString(amount: string | bigint, currency: string): string {
  const minor = displayMinor(amount, currency);
  const text = scaledString(minor, fractionDigits(currency), true);
  return minor === 0n && isNegativeAmount(amount) ? "-" + text : text;
}
export function convertAmountText(input: string, currency: string): string {
  const value = decimalFromInput(input.trim());
  return value === null ? "" : plainAmountString(value, currency);
}
export function formatMoney(money: Money, locale?: string): string;
export function formatMoney(amount: string | bigint, currency: string, locale?: string): string;
export function formatMoney(input: string | bigint | Money, currencyOrLocale?: string, _requestedLocale = "en-US"): string {
  const amount = typeof input === "object" ? input.amount : input;
  const currency = typeof input === "object" ? input.currency : currencyOrLocale;
  if (currency === undefined) throw new Error("Currency is required.");
  const metadata = displayMetadata(currency),
    minor = displayMinor(amount, currency);
  const fixed = scaledString(abs(minor), metadata.fractionDigits, true);
  const [whole = "0", fraction] = fixed.split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const value = (isNegativeAmount(amount) ? "-" : "") + grouped + (fraction ? "." + fraction : "");
  return metadata.symbol.toUpperCase() === metadata.code ? metadata.code + " " + value : metadata.symbol + value;
}
export function formatSigned(amount: string | bigint, currency: string, locale = "en-US"): string {
  const minor = displayMinor(amount, currency);
  return (isNegativeAmount(amount) ? "-" : "") + formatMoney(abs(minor), currency, locale);
}
export const MoneyFormatter = {
  format: formatMoney,
  formatSigned,
  plainAmountString,
  convertAmountText,
  sanitizeAmountInput,
  sanitizeShareInput,
  shareString,
  decimal: decimalFromInput,
  currencySymbol: (code: string) => displayMetadata(code).symbol,
  amountPlaceholder: (currency: string) => plainAmountString(0n, currency),
};
