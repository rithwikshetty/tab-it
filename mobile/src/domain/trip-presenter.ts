import { formatCalendarDate, type TimeZoneOffset } from "./expense-dates";
import type { TripRows } from "./models";
import { balancesFromRows } from "./balance-engine";
import { mirroredSimplifiedBalances } from "./debt-simplifier";
import { deriveTripState } from "./trip-state-deriver";
import {
  avatarInitial,
  avatarTone,
  sortedPeople,
} from "./presentation-helpers";
import { abs } from "./decimal";
import { formatMoney } from "./money-formatter";
export interface TripCardStatus {
  type: "owed" | "owe" | "mixed" | "settled" | "empty";
  text: string;
}
export function tripCard(
  rows: TripRows,
  currentPersonID: string,
  now: string,
  currentUserDisplayName?: string,
  locale = "en-US",
  timeZone: TimeZoneOffset = "UTC",
) {
  const balances = balancesFromRows(rows),
    state = deriveTripState(
      mirroredSimplifiedBalances(balances),
      rows.trip.last_activity_at,
      now,
    ),
    nets = new Map<string, bigint>();
  for (const b of balances.filter((b) => b.forUser === currentPersonID))
    nets.set(b.currency, (nets.get(b.currency) ?? 0n) + b.amount);
  const values = [...nets]
    .filter(([, n]) => n !== 0n)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  let status: TripCardStatus;
  if (state === "completed")
    status = {
      type: "settled",
      text:
        "settled · " +
        formatCalendarDate(rows.trip.last_activity_at, "MMM yyyy", timeZone),
    };
  else if (!values.length)
    status =
      rows.expenses.some((e) => !e.deleted_at) ||
      rows.settlements.some((s) => !s.deleted_at)
        ? { type: "settled", text: "all settled" }
        : { type: "empty", text: "" };
  else if (values.every(([, n]) => n > 0n))
    status = {
      type: "owed",
      text:
        "you're owed " +
        values.map(([c, n]) => formatMoney(n, c, locale)).join(" + "),
    };
  else if (values.every(([, n]) => n < 0n))
    status = {
      type: "owe",
      text:
        "you owe " +
        values.map(([c, n]) => formatMoney(-n, c, locale)).join(" + "),
    };
  else
    status = {
      type: "mixed",
      text:
        "net " +
        values
          .map(
            ([c, n]) => (n > 0n ? "+" : "-") + formatMoney(abs(n), c, locale),
          )
          .join(" "),
    };
  return {
    id: rows.trip.id,
    name: rows.trip.name,
    members: sortedPeople(
      rows.people.filter((p) => !p.removed_at),
      currentPersonID,
    ).map((p) => ({
      id: p.id,
      displayName: p.id === currentPersonID ? "You" : p.display_name,
      initial: avatarInitial(
        p.id === currentPersonID
          ? (currentUserDisplayName ?? p.display_name)
          : p.display_name,
      ),
      tone: avatarTone(p.id),
    })),
    status,
    isCompleted: state === "completed",
  };
}
export const TripPresenter = { card: tripCard };
