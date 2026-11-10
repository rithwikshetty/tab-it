import { expect, test } from "vitest";

import { TABLE_NAMES, type State } from "./schema";
import { unsyncedChanges } from "./selectors";

function state(rows: Partial<Record<(typeof TABLE_NAMES)[number], [string, object][]>>): State {
  return {
    tables: Object.fromEntries(TABLE_NAMES.map((t) => [t, new Map(rows[t] ?? [])])) as unknown as State["tables"],
    meta: new Map(),
  };
}

test("lists waiting and refused receipt photos, a renamed profile and a mute change", () => {
  const synced = { write_id: "w1", _pushed: "w1" };
  const dirty = { write_id: "w2", _pushed: "w1" };
  const changes = unsyncedChanges(
    state({
      trips: [["trip", { id: "trip", kind: "trip", name: "Lisbon", deleted_at: null, ...synced }]],
      expenses: [
        ["dinner", { id: "dinner", trip_id: "trip", description: "Dinner", deleted_at: null, _receipt: "pending", ...synced }],
        ["taxi", { id: "taxi", trip_id: "trip", description: "Taxi", deleted_at: null, _receipt: "pending", ...dirty }],
        ["lunch", { id: "lunch", trip_id: "trip", description: "Lunch", deleted_at: null, _receipt: "failed", ...synced }],
      ],
      profiles: [
        ["me", { id: "me", display_name: "Sam", ...dirty }],
        ["friend", { id: "friend", display_name: "Alex", ...synced }],
      ],
      trip_mute_prefs: [["trip:me", { trip_id: "trip", user_id: "me", _deleted: true, ...dirty, _error: "Refused" }]],
    }),
  );
  expect(changes.map((c) => [c.table, c.key, c.label, c.detail, c.error])).toEqual([
    ["expenses", "taxi", "Taxi", "Expense in Lisbon", null],
    ["receipts", "dinner", "Dinner", "Receipt photo in Lisbon", null],
    ["receipts", "lunch", "Lunch", "Receipt photo in Lisbon", "The photo couldn't be uploaded."],
    ["profiles", "me", "Sam", "Your name", null],
    ["trip_mute_prefs", "trip:me", "Lisbon", "Unmute notifications", "Refused"],
  ]);
});
