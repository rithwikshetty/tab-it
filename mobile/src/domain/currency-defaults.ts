import {
  defaultCurrencyCode,
  isSupportedCurrency,
  normalizedCode,
} from "./currency-catalog";
import type { Expense, Settlement } from "./records";
import { timestampUnits } from "./conflict-resolver";
export function validCurrency(code: string | null | undefined): string | null {
  return code && isSupportedCurrency(code) ? normalizedCode(code) : null;
}
export function initialCurrency(
  savedCurrency?: string | null,
  regionCurrency?: string | null,
): string {
  return (
    validCurrency(savedCurrency) ??
    validCurrency(regionCurrency) ??
    defaultCurrencyCode
  );
}
export function mostRecentTripCurrency(
  expenses: readonly Expense[],
  settlements: readonly Settlement[],
): string | null {
  const candidates = [...expenses, ...settlements]
    .filter((r) => !r.deleted_at && isSupportedCurrency(r.currency))
    .map((r) => ({
      currency: normalizedCode(r.currency),
      date:
        timestampUnits(r.updated_at) > timestampUnits(r.created_at)
          ? timestampUnits(r.updated_at)
          : timestampUnits(r.created_at),
    }));
  candidates.sort((a, b) =>
    a.date !== b.date
      ? a.date > b.date
        ? -1
        : 1
      : a.currency < b.currency
        ? -1
        : a.currency > b.currency
          ? 1
          : 0,
  );
  return candidates[0]?.currency ?? null;
}
export function defaultCurrency(
  expenses: readonly Expense[],
  settlements: readonly Settlement[],
  savedCurrency?: string | null,
  regionCurrency?: string | null,
): string {
  return (
    mostRecentTripCurrency(expenses, settlements) ??
    initialCurrency(savedCurrency, regionCurrency)
  );
}
export const CurrencyDefaults = {
  fallbackCode: defaultCurrencyCode,
  initialCurrency,
  defaultCurrency,
  mostRecentTripCurrency,
  lastSelectedCurrency: validCurrency,
  deviceRegionCurrency: validCurrency,
  remember: (code: string, saved: string | null = null) =>
    validCurrency(code) ?? saved,
};
