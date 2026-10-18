import type { UserBalance } from "./balance-engine";
import { timestampUnits } from "./conflict-resolver";
export type TripState = "active" | "completed";
export const defaultInactivityThreshold = 30 * 24 * 60 * 60;
export function deriveTripState(
  balances: readonly UserBalance[],
  lastActivityAt: string,
  now: string,
  inactivityThreshold = defaultInactivityThreshold,
): TripState {
  if (balances.some((b) => b.amount !== 0n)) return "active";
  return timestampUnits(now) - timestampUnits(lastActivityAt) >= BigInt(Math.round(inactivityThreshold * 1000000000))
    ? "completed"
    : "active";
}
export const TripStateDeriver = {
  derive: deriveTripState,
  defaultInactivityThreshold,
};
