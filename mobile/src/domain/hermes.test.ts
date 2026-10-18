import { afterEach, expect, test, vi } from "vitest";
import type { ActivityLogEntry } from "./records";
import { a, b, addExpense, tripRows, person, now } from "./test-support";
afterEach(() => vi.unstubAllGlobals());
test("the whole domain works when Intl and browser text encoders are unavailable", async () => {
  vi.stubGlobal("Intl", undefined);
  vi.stubGlobal("TextEncoder", undefined);
  vi.resetModules();
  const domain = await import("./index");
  const rows = addExpense(
    tripRows("trip", "Lisbon", [person(a, "Alice"), person(b, "Bob")]),
    "e",
    { [a]: "30" },
    { [a]: "15", [b]: "15" },
    "30",
    "GBP",
  );
  expect(domain.formatMoney(99999999999999999999n, "USD")).toBe(
    "$999,999,999,999,999,999.99",
  );
  expect(domain.formatMoney("-12.5", "GBP")).toBe("£-12.50");
  expect(domain.formatSigned("-12.5", "GBP")).toBe("-£12.50");
  expect(domain.formatMoney("12.5", "CHF")).toBe("CHF 12.50");
  expect(domain.formatMoney("123", "JPY")).toBe("¥123");
  expect(domain.formatMoney("1.234", "KWD")).toMatch(/1\.234$/);
  expect(domain.tripCard(rows, a, now).status.text).toBe("you're owed £15.00");
  expect(
    domain.tripCard(tripRows(), a, "2026-07-01T00:00:00Z").status.text,
  ).toBe("settled · May 2026");
  expect(
    domain.timelineDays(rows, rows.people, [], a, { utcOffsetMinutes: 840 })[0]
      ?.dateLabel,
  ).toBe("May 22");
  expect(domain.friendsList([rows], a).active[0]?.displayName).toBe("Bob");
  expect(domain.avatarInitial("👩‍💻 Alex")).toBe("👩‍💻");
  expect(domain.normalizedDisplayName("  Émile  ")).toBe("Émile");
  expect(domain.searchCurrencies("yen").some((c) => c.code === "JPY")).toBe(
    true,
  );
  const activity: ActivityLogEntry = {
    id: "activity",
    trip_id: "trip",
    actor_id: b,
    action: "expense_created",
    entity_type: "expense",
    entity_id: "e",
    timestamp: "2026-05-22T20:30:00Z",
    snapshot_json: {
      actor_name: "Bob",
      description: "Dinner",
      amount: "30",
      currency: "GBP",
    },
  };
  const options = {
    currentUserID: a,
    lastSeenAt: null,
    mutedTripIDs: new Set<string>(),
    utcOffsetMinutes: 330,
  };
  expect(domain.activityRow(activity, options).timeText).toBe("2:00 AM");
  expect(
    domain.activitySections([activity], options, "2026-05-23T00:00:00Z")[0]
      ?.dateLabel,
  ).toBe("Today");
  const data = domain.extractExportData(rows, "en-US", 330);
  expect(data.expenses[0]?.createdAt).toBe("2026-05-23 02:00");
  const bytes = domain.workbookXLSX(domain.buildWorkbook(data));
  expect(Array.from(bytes.slice(0, 4))).toEqual([0x50, 0x4b, 0x03, 0x04]);
  expect(Array.from(domain.utf8Bytes("£👩‍💻"))).toEqual([
    194, 163, 240, 159, 145, 169, 226, 128, 141, 240, 159, 146, 187,
  ]);
});
