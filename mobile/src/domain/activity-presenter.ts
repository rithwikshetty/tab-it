import type { ActivityLogEntry } from "./records";
import type { CalendarOptions } from "./expense-dates";
import {
  calendarDay,
  displayExpenseDate,
  formatClockTime,
  calendarOffset,
} from "./expense-dates";
import { decimalFromInput } from "./money";
import { formatMoney } from "./money-formatter";
import { timestampUnits } from "./conflict-resolver";
export type ActivityTarget =
  | {
      type: "trip";
      tripID: string;
    }
  | {
      type: "expense";
      tripID: string;
      expenseID: string;
    }
  | {
      type: "settlement";
      tripID: string;
      settlementID: string;
    };
export interface ActivityLocalState {
  readAt?: string | null;
  dismissedAt?: string | null;
}
export interface ActivityOptions extends CalendarOptions {
  currentUserID: string;
  lastSeenAt: string | null;
  mutedTripIDs: ReadonlySet<string>;
  myTripPersonIDs?: ReadonlySet<string>;
  joinedAtByTrip?: Readonly<Record<string, string>>;
  localState?: Readonly<Record<string, ActivityLocalState>>;
}
export function isActivityUnread(
  a: ActivityLogEntry,
  options: ActivityOptions,
): boolean {
  const local = options.localState?.[a.id];
  return (
    a.actor_id !== options.currentUserID &&
    !options.mutedTripIDs.has(a.trip_id) &&
    !local?.readAt &&
    !local?.dismissedAt &&
    (options.lastSeenAt === null ||
      timestampUnits(a.timestamp) > timestampUnits(options.lastSeenAt)) &&
    (!options.joinedAtByTrip?.[a.trip_id] ||
      timestampUnits(a.timestamp) >=
        timestampUnits(options.joinedAtByTrip[a.trip_id]!))
  );
}
export function unreadActivityCount(
  activities: readonly ActivityLogEntry[],
  options: ActivityOptions,
): number {
  return activities.filter((a) => isActivityUnread(a, options)).length;
}
export function activityRow(a: ActivityLogEntry, options: ActivityOptions) {
  const snapshot = a.snapshot_json ?? {};
  const s = Object.values(snapshot).every((value) => typeof value === "string")
    ? snapshot
    : {};
  const get = (key: string) =>
    typeof s[key] === "string" ? (s[key] as string) : undefined;
  const actor = get("actor_name") ?? "Someone",
    trip = get("trip_name") ?? "a trip",
    description = get("description") ?? "an expense";
  let icon = "bell.fill",
    isNegative = false,
    title = `${actor} updated ${trip}`,
    detail: string | null = null,
    target: ActivityTarget = { type: "trip", tripID: a.trip_id };
  switch (a.action) {
    case "expense_created":
      icon = "plus.circle.fill";
      title = `${actor} added ${description}`;
      target = { type: "expense", tripID: a.trip_id, expenseID: a.entity_id };
      break;
    case "expense_updated":
      icon = "pencil.circle.fill";
      title = `${actor} edited ${description}`;
      target = { type: "expense", tripID: a.trip_id, expenseID: a.entity_id };
      break;
    case "expense_deleted":
      icon = "trash.circle.fill";
      isNegative = true;
      title = `${actor} deleted ${description}`;
      break;
    case "settlement_created":
    case "settlement_updated":
    case "settlement_deleted":
      icon = "arrow.left.arrow.right.circle.fill";
      isNegative = a.action === "settlement_deleted";
      title = `${actor} ${a.action === "settlement_created" ? "recorded" : a.action === "settlement_updated" ? "edited" : "removed"} a payment`;
      detail =
        get("from_name") !== undefined && get("to_name") !== undefined
          ? `${get("from_name")} → ${get("to_name")}`
          : null;
      if (!isNegative)
        target = {
          type: "settlement",
          tripID: a.trip_id,
          settlementID: a.entity_id,
        };
      break;
    case "member_joined":
      icon = "person.crop.circle.badge.plus";
      title = options.myTripPersonIDs?.has(a.entity_id)
        ? `You were added to ${trip}`
        : `${actor} added ${get("member_name") ?? "someone"}`;
      break;
    case "member_left":
      icon = "person.crop.circle.badge.minus";
      isNegative = true;
      title = `${actor} removed ${get("member_name") ?? "someone"}`;
      break;
    case "trip_created":
      icon = "suitcase.fill";
      title = `${actor} created ${trip}`;
      break;
    case "trip_updated":
      icon = "pencil";
      title = `${actor} renamed the trip to ${trip}`;
      break;
  }
  const amount =
    get("amount") !== undefined ? decimalFromInput(get("amount")!) : null;
  const trailing =
    amount !== null && get("currency") !== undefined
      ? formatMoney(amount, get("currency")!, options.locale)
      : null;
  return {
    id: a.id,
    icon,
    isNegative,
    title,
    detail,
    trailing,
    tripName: trip,
    timeText: formatClockTime(a.timestamp, calendarOffset(options)),
    isUnread: isActivityUnread(a, options),
    target,
  };
}
export function activitySections(
  activities: readonly ActivityLogEntry[],
  options: ActivityOptions,
  now: string,
) {
  const { locale = "en-US" } = options;
  const timeZone = calendarOffset(options);
  const today = calendarDay(now, timeZone),
    yesterday = new Date(today + "T12:00:00Z");
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const yesterdayKey = yesterday.toISOString().slice(0, 10),
    sorted = activities
      .filter((a) => !options.localState?.[a.id]?.dismissedAt)
      .slice()
      .sort((a, b) =>
        timestampUnits(a.timestamp) > timestampUnits(b.timestamp)
          ? -1
          : timestampUnits(a.timestamp) < timestampUnits(b.timestamp)
            ? 1
            : 0,
      );
  return [
    ...new Set(sorted.map((a) => calendarDay(a.timestamp, timeZone))),
  ].map((id) => ({
    id,
    dateLabel:
      id === today
        ? "Today"
        : id === yesterdayKey
          ? "Yesterday"
          : displayExpenseDate(
              id,
              id.slice(0, 4) === today.slice(0, 4)
                ? "EEEE, MMM d"
                : "MMM d, yyyy",
              locale,
            ),
    rows: sorted
      .filter((a) => calendarDay(a.timestamp, timeZone) === id)
      .map((a) => activityRow(a, options)),
  }));
}
export function activityNavigation(
  target: ActivityTarget,
  expenseIsOpenable: (id: string) => boolean,
  settlementIsOpenable: (id: string) => boolean,
): {
  type: "trip" | "expense" | "settlement";
  id: string;
}[] {
  if (target.type === "expense" && expenseIsOpenable(target.expenseID))
    return [{ type: "expense", id: target.expenseID }];
  if (target.type === "settlement" && settlementIsOpenable(target.settlementID))
    return [{ type: "settlement", id: target.settlementID }];
  return [{ type: "trip", id: target.tripID }];
}
export const ActivityPresenter = {
  sections: activitySections,
  unreadCount: unreadActivityCount,
};
export const ActivityNavigation = { stack: activityNavigation };
