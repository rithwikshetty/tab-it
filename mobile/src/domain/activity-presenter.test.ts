import { expect, test } from "vitest";
import {
  activitySections as sections,
  unreadActivityCount as count,
  activityRow,
  activityNavigation,
  type ActivityOptions,
} from "./activity-presenter";
import type { ActivityLogEntry } from "./records";
import { a, b } from "./test-support";
const seen = "2027-01-15T08:00:00Z";
const at = (seconds: number) => new Date(Date.parse(seen) + seconds * 1000).toISOString();
const activity = (id: string, seconds = 60, extra: Partial<ActivityLogEntry> = {}): ActivityLogEntry => ({
  id,
  trip_id: "trip",
  actor_id: b,
  action: "expense_created",
  entity_type: "expense",
  entity_id: id,
  timestamp: at(seconds),
  snapshot_json: {
    actor_name: "Bo",
    trip_name: "Lisbon",
    description: "Dinner",
    amount: "40.00",
    currency: "EUR",
  },
  ...extra,
});
const options = (extra: Partial<ActivityOptions> = {}): ActivityOptions => ({
  currentUserID: a,
  lastSeenAt: seen,
  mutedTripIDs: new Set(),
  myTripPersonIDs: new Set(),
  ...extra,
});
test("feedShowsOwnActivityWithoutMarkingItUnread", () => {
  const r = sections(
    [
      activity("own", 120, {
        actor_id: a,
        snapshot_json: {
          actor_name: "You",
          trip_name: "Lisbon",
          description: "Coffee",
          amount: "6.00",
          currency: "EUR",
        },
      }),
      activity("other"),
    ],
    options(),
    seen,
  ).flatMap((s) => s.rows);
  expect(r.map((r) => r.target)).toEqual([
    { type: "expense", tripID: "trip", expenseID: "own" },
    { type: "expense", tripID: "trip", expenseID: "other" },
  ]);
  expect(r.map((r) => r.isUnread)).toEqual([false, true]);
});
test("readActivityIsNotUnreadEvenWhenNewerThanCursor", () =>
  expect(
    sections([activity("read")], options({ localState: { read: { readAt: at(90) } } }), seen)
      .flatMap((s) => s.rows)
      .map((r) => r.isUnread),
  ).toEqual([false]));
test("unreadActivityRequiresNilReadMarkerAndNewerTimestamp", () =>
  expect(
    sections([activity("new")], options(), seen)
      .flatMap((s) => s.rows)
      .map((r) => r.isUnread),
  ).toEqual([true]));
test("unreadCountStillExcludesOwnActivity", () =>
  expect(
    count(
      [activity("own", 120, { actor_id: a, action: "settlement_created" }), activity("other", 60, { action: "settlement_created" })],
      options(),
    ),
  ).toBe(1));
test("preJoinEventsAreNotUnread", () =>
  expect(count([activity("old", -3600), activity("new", 60)], options({ lastSeenAt: null, joinedAtByTrip: { trip: seen } }))).toBe(1));
test("mutedTripsAreNotUnread", () =>
  expect(
    sections([activity("muted", 60, { trip_id: "muted" })], options({ mutedTripIDs: new Set(["muted"]) }), seen)
      .flatMap((s) => s.rows)
      .map((r) => r.isUnread),
  ).toEqual([false]));
test("unreadCountFollowsReadMarkerActorMuteAndCursorRules", () =>
  expect(
    count(
      [
        activity("new"),
        activity("read", 120),
        activity("own", 180, { actor_id: a }),
        activity("muted", 240, { trip_id: "muted" }),
        activity("past", -60),
      ],
      options({
        mutedTripIDs: new Set(["muted"]),
        localState: { read: { readAt: at(150) } },
      }),
    ),
  ).toBe(1));
test("dismissedActivityIsHiddenAndNeverUnread", () => {
  const acts = [
      activity("dismissed"),
      activity("coffee", 120, {
        snapshot_json: {
          actor_name: "Bo",
          trip_name: "Lisbon",
          description: "Coffee",
        },
      }),
    ],
    o = options({ localState: { dismissed: { dismissedAt: at(90) } } });
  expect(
    sections(acts, o, seen)
      .flatMap((s) => s.rows)
      .map((r) => r.title),
  ).toEqual(["Bo added Coffee"]);
  expect(count(acts, o)).toBe(1);
});
test("openableExpenseActivityGoesStraightToExpenseDetail", () =>
  expect(
    activityNavigation(
      { type: "expense", tripID: "trip", expenseID: "e" },
      (id) => id === "e",
      () => false,
    ),
  ).toEqual([{ type: "expense", id: "e" }]));
test("missingExpenseActivityFallsBackToTrip", () =>
  expect(
    activityNavigation(
      { type: "expense", tripID: "trip", expenseID: "e" },
      () => false,
      () => false,
    ),
  ).toEqual([{ type: "trip", id: "trip" }]));
test("openableSettlementActivityGoesStraightToSettlementDetail", () =>
  expect(
    activityNavigation(
      { type: "settlement", tripID: "trip", settlementID: "s" },
      () => false,
      (id) => id === "s",
    ),
  ).toEqual([{ type: "settlement", id: "s" }]));
test.each([
  ["expense_created", "Bo added Dinner", false, "expense"],
  ["expense_updated", "Bo edited Dinner", false, "expense"],
  ["expense_deleted", "Bo deleted Dinner", true, "trip"],
  ["settlement_created", "Bo recorded a payment", false, "settlement"],
  ["settlement_updated", "Bo edited a payment", false, "settlement"],
  ["settlement_deleted", "Bo removed a payment", true, "trip"],
  ["member_joined", "Bo added someone", false, "trip"],
  ["member_left", "Bo removed someone", true, "trip"],
  ["trip_created", "Bo created Lisbon", false, "trip"],
  ["trip_updated", "Bo renamed the trip to Lisbon", false, "trip"],
] as const)("row mapping %s", (action, title, isNegative, target) => {
  const row = activityRow(activity("x", 60, { action }), options());
  expect(row.title).toBe(title);
  expect(row.isNegative).toBe(isNegative);
  expect(row.target.type).toBe(target);
  expect(row.trailing).toBe("€40.00");
});
test("snapshot fallbacks and join-self title", () => {
  expect(activityRow(activity("self", 60, { action: "member_joined" }), options({ myTripPersonIDs: new Set(["self"]) })).title).toBe(
    "You were added to Lisbon",
  );
  expect(
    activityRow(
      activity("s", 60, {
        action: "settlement_created",
        snapshot_json: { from_name: "A", to_name: "B" },
      }),
      options(),
    ),
  ).toMatchObject({
    title: "Someone recorded a payment",
    detail: "A → B",
    trailing: null,
  });
});
test("feed date labels use the supplied clock", () => {
  const s = sections([activity("today"), activity("yesterday", -86400), activity("old", -400 * 86400)], options(), seen);
  expect(s[0]?.dateLabel).toBe("Today");
  expect(s[1]?.dateLabel).toBe("Yesterday");
  expect(s[2]?.dateLabel).toMatch(/2025/);
});
test("non-string snapshots match Swift whole-dictionary decode fallback", () =>
  expect(activityRow(activity("x", 60, { snapshot_json: { actor_name: "Bo", amount: 40 } }), options()).title).toBe(
    "Someone added an expense",
  ));
