import type { SplitType, UUID } from "./records";
import type { CalculatedSplit } from "./models";
import { hasValidPrecision, fractionDigits, normalizedCode } from "./currency-catalog";
import { toMinor } from "./money";
import { addDecimals, allocateMinor, decimalRational, floorDivide, normalizeDecimal, scaledString } from "./decimal";
export class CalculationError extends Error {
  constructor(
    public readonly code: string,
    public readonly details: Record<string, string | number> = {},
  ) {
    super(code);
    this.name = "CalculationError";
  }
}
export interface SplitOptions {
  totalAmount: string;
  currency: string;
  participants: readonly UUID[];
  splitType: SplitType;
  exactAmounts?: Readonly<Record<UUID, string>>;
  shares?: Readonly<Record<UUID, string>>;
  percentages?: Readonly<Record<UUID, string>>;
}
export function calculateSplits({
  totalAmount,
  currency,
  participants,
  splitType,
  exactAmounts,
  shares,
  percentages,
}: SplitOptions): CalculatedSplit[] {
  const fail = (code: string, details?: Record<string, string | number>): never => {
    throw new CalculationError(code, details);
  };
  if (!participants.length) fail("emptyParticipants");
  const seen = new Set<string>();
  for (const id of participants) {
    if (seen.has(id)) fail("duplicateParticipant", { id });
    seen.add(id);
  }
  const validate = (value: string) => {
    if (!hasValidPrecision(value, currency))
      fail("amountHasTooManyFractionDigits", {
        currency: normalizedCode(currency),
        maximumFractionDigits: fractionDigits(currency),
      });
  };
  validate(totalAmount);
  const total = toMinor(totalAmount, currency);
  let amounts: Record<string, bigint>;
  if (splitType === "equal") {
    const n = BigInt(participants.length),
      base = floorDivide(total, n),
      remainder = total - base * n;
    const bonuses = new Set([...participants].sort().filter((_, i) => BigInt(i) < remainder));
    amounts = Object.fromEntries(participants.map((id) => [id, base + (bonuses.has(id) ? 1n : 0n)]));
  } else if (splitType === "exact" || splitType === "shares" || splitType === "percentage") {
    const values = splitType === "exact" ? exactAmounts : splitType === "shares" ? shares : percentages;
    const unit = splitType === "exact" ? "Amount" : splitType === "shares" ? "Share" : "Percentage";
    if (!values) fail(splitType === "exact" ? "exactAmountsRequired" : splitType === "shares" ? "sharesRequired" : "percentagesRequired");
    const entries = values!;
    for (const id of Object.keys(entries)) if (!seen.has(id)) fail(`extra${unit}ForNonParticipant`, { id });
    for (const id of participants) if (entries[id] === undefined) fail(`missing${unit}ForParticipant`, { id });
    if (splitType === "exact") {
      Object.values(entries).forEach(validate);
      const actual = addDecimals(Object.values(entries));
      if (normalizeDecimal(totalAmount) !== actual)
        fail("amountsDoNotSumToTotal", {
          expected: normalizeDecimal(totalAmount),
          actual,
        });
      amounts = Object.fromEntries(participants.map((id) => [id, toMinor(entries[id]!, currency)]));
    } else {
      for (const id of [...participants].sort()) if (decimalRational(entries[id]!).numerator <= 0n) fail(`nonPositive${unit}`, { id });
      const actual = addDecimals(participants.map((id) => entries[id]!));
      if (splitType === "percentage" && actual !== "100") fail("percentagesDoNotSumTo100", { actual });
      amounts = allocateMinor(total, participants, entries);
    }
  } else return fail("unsupportedSplitType", { splitType });
  return participants.map((id) => ({
    participantID: id,
    amountOwed: amounts[id]!,
    splitType,
    shareUnits: splitType === "shares" ? normalizeDecimal(shares![id]!) : null,
    percentage: splitType === "percentage" ? normalizeDecimal(percentages![id]!) : null,
  }));
}
export function equalPercentages(participants: readonly UUID[]): Record<UUID, string> {
  if (!participants.length) return {};
  const n = BigInt(participants.length),
    base = 10000n / n,
    remainder = 10000n % n;
  return Object.fromEntries([...participants].sort().map((id, i) => [id, scaledString(base + (BigInt(i) < remainder ? 1n : 0n), 2)]));
}
export const SplitCalculator = { calculate: calculateSplits, equalPercentages };
