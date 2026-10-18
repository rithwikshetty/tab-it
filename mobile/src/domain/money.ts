import type { DecimalString } from "./records";
import { fractionDigits, minorUnitMultiplier } from "./currency-catalog";
import {
  decimalRational,
  roundDivide,
  scaledString,
  normalizeDecimal,
} from "./decimal";
export {
  fractionDigits,
  minorUnitMultiplier,
  hasValidPrecision,
  normalizedAmount,
} from "./currency-catalog";
export interface Money {
  amount: bigint;
  currency: string;
}
export function toMinor(
  decimalString: DecimalString,
  currency: string,
): bigint {
  const r = decimalRational(decimalString);
  return roundDivide(
    r.numerator * minorUnitMultiplier(currency),
    r.denominator,
  );
}
export function fromMinor(amount: bigint, currency: string): DecimalString {
  return scaledString(amount, fractionDigits(currency));
}
export function parseMoney(amount: DecimalString, currency: string): Money {
  const code = currency.trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(code))
    throw new Error("Currency must be a three-letter uppercase code.");
  return { amount: toMinor(amount, code), currency: code };
}
export function sanitizeAmountInput(input: string, currency: string): string {
  const kept = input.replace(/[^\p{N}.,]/gu, "");
  const dots = (kept.match(/\./g) ?? []).length,
    commas = (kept.match(/,/g) ?? []).length;
  let normalized = kept;
  if (dots && commas)
    normalized = kept
      .replace(kept.lastIndexOf(".") > kept.lastIndexOf(",") ? /,/g : /\./g, "")
      .replace(/,/g, ".");
  else if (dots > 1) normalized = kept.replace(/\./g, "");
  else if (commas > 1) normalized = kept.replace(/,/g, "");
  else normalized = kept.replace(/,/g, ".");
  const digits = fractionDigits(currency);
  let output = "",
    decimal = false,
    count = 0;
  for (const c of normalized) {
    if (/\p{N}/u.test(c)) {
      if (decimal && count++ >= digits) break;
      output += c;
    } else if (c === ".") {
      if (!digits || decimal) break;
      decimal = true;
      output += c;
    }
  }
  return output;
}
export function decimalFromInput(input: string): DecimalString | null {
  const text = input.replace(/,/g, ".").trimStart();
  const match = /^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(?:[eE]([+-]?\d+))?/.exec(text);
  if (!match) return null;
  if (!match[2]) return normalizeDecimal(match[1]!);
  const r = decimalRational(match[1]!),
    exponent = BigInt(match[2]);
  if (exponent > 128n || exponent < -128n) return null;
  const numerator = exponent > 0n ? r.numerator * 10n ** exponent : r.numerator;
  const denominator =
    exponent < 0n ? r.denominator * 10n ** -exponent : r.denominator;
  return scaledString(numerator, denominator.toString().length - 1);
}
export function parseAmountInput(
  input: string,
  currency: string,
): bigint | null {
  const value = decimalFromInput(sanitizeAmountInput(input, currency));
  return value === null ? null : toMinor(value, currency);
}
export function sanitizeShareInput(input: string): string {
  let output = "",
    decimal = false,
    count = 0;
  for (const c of input) {
    if (/\p{N}/u.test(c)) {
      if (decimal && count++ >= 2) break;
      output += c;
    } else if (c === "." || c === ",") {
      if (decimal) break;
      decimal = true;
      output += ".";
    }
  }
  return output;
}
export function shareString(value: string): string {
  const r = decimalRational(value);
  return scaledString(roundDivide(r.numerator * 100n, r.denominator), 2);
}
export function addMoney(a: Money, b: Money): Money {
  if (a.currency !== b.currency)
    throw new Error("Cannot add different currencies.");
  return { amount: a.amount + b.amount, currency: a.currency };
}
