import { getLocales } from "expo-localization";

import type { Ctx } from "@/data/actions";
import type { State } from "@/data/schema";
import { defaultCurrency, initialCurrency, validCurrency } from "@/domain";

// Which currency a new expense or payment starts in: the trip's most recent
// one, else the last currency the user picked, else the phone's region.

const KEY = "pref.currency";

function regionCurrency(): string | null {
  try {
    return getLocales()[0]?.currencyCode ?? null;
  } catch {
    return null;
  }
}

export function savedCurrency(state: State): string | null {
  return validCurrency(state.meta.get(KEY));
}

export function currencyFor(state: State, tripId: string | null): string {
  if (!tripId) return initialCurrency(savedCurrency(state), regionCurrency());
  const expenses = [...state.tables.expenses.values()].filter((e) => e.trip_id === tripId);
  const settlements = [...state.tables.settlements.values()].filter((s) => s.trip_id === tripId);
  return defaultCurrency(expenses, settlements, savedCurrency(state), regionCurrency());
}

export function rememberCurrency({ store }: Ctx, code: string) {
  const valid = validCurrency(code);
  if (valid && store.getState().meta.get(KEY) !== valid) void store.commit([{ meta: KEY, value: valid }]);
}
