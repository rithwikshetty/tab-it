import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { addDecimals } from "@/domain/decimal";
import { TABLE_NAMES, type Op, type State } from "../schema";
import {
  ACTIVITY_SEEN, LEGACY_TABLES, LegacyAccountMismatch,
  convertLegacyRows, legacyDecimal, legacyTimestamp,
  legacyUUID, selectLegacyOps, type LegacyRow, type LegacyRows,
} from "./convert";
import { pendingLegacyActivitySeen } from "./preferences";
import { legacySelect, readLegacyRows } from "./reader";

const userId = "11111111-1111-1111-1111-111111111111";
const fixture = fileURLToPath(new URL("./fixtures/default.store", import.meta.url));

async function fixtureRows(): Promise<LegacyRows> {
  const db = new DatabaseSync(fixture, { readOnly: true });
  try {
    return await readLegacyRows({ async getAllAsync<T>(sql: string) { return db.prepare(sql).all() as T[]; } });
  } finally { db.close(); }
}

function emptyState(): State {
  return { tables: Object.fromEntries(TABLE_NAMES.map((name) => [name, new Map()])) as unknown as State["tables"], meta: new Map() };
}

function upserts(ops: readonly Op[]) {
  return ops.filter((op) => "row" in op);
}

describe("the captured SwiftData store", () => {
  it("converts every model row, including clean rows and full expense ledgers", async () => {
    const rows = await fixtureRows();
    const ops = convertLegacyRows(rows, userId);
    expect(upserts(ops)).toHaveLength(LEGACY_TABLES.reduce((n, table) => n + rows[table].length, 0));
    const expenses = upserts(ops).filter((op) => op.table === "expenses").map((op) => op.row);
    expect(expenses).toHaveLength(12);
    for (const e of expenses) {
      expect(e._pushed).toBeNull();
      expect(e.expense_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(e.created_at).toMatch(/\.\d{6}Z$/);
      const paid = upserts(ops).filter((op) => op.table === "expense_payments").filter((op) => op.row.expense_id === e.id);
      const owed = upserts(ops).filter((op) => op.table === "expense_splits").filter((op) => op.row.expense_id === e.id);
      expect(addDecimals(paid.map((op) => op.row.amount_paid))).toBe(e.amount);
      expect(addDecimals(owed.map((op) => op.row.amount_owed))).toBe(e.amount);
    }
  });

  it("retains the acknowledged write ID separately from the current ID", async () => {
    const rows = await fixtureRows();
    rows.ZTRIPENTITY[0]!.ZPUSHEDWRITEID = rows.ZTRIPENTITY[0]!.ZWRITEID!;
    rows.ZTRIPPERSONENTITY[0]!.ZPUSHEDWRITEID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    const ops = upserts(convertLegacyRows(rows, userId));
    const trip = ops.find((op) => op.table === "trips")!;
    const person = ops.find((op) => op.table === "trip_people")!;
    expect(trip.row._pushed).toBe(trip.row.write_id);
    expect(person.row._pushed).toBe("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    expect(person.row._pushed).not.toBe(person.row.write_id);
  });

  it("carries pending receipts, unmute tombstones, profile edits, and read/dismiss state", async () => {
    const rows = await fixtureRows();
    const path = rows.ZEXPENSEENTITY.find((r) => r.ZRECEIPTSTORAGEPATH)?.ZRECEIPTSTORAGEPATH as string;
    const pending = pendingLegacyActivitySeen(readFileSync(new URL("./fixtures/preferences.plist", import.meta.url)), userId);
    const ops = convertLegacyRows(rows, userId, { pendingReceiptPaths: new Set([path]), pendingActivitySeenAt: pending });
    expect(upserts(ops).filter((op) => op.table === "expenses").find((op) => op.row.receipt_storage_path === path)?.row._receipt).toBe("pending");
    expect(upserts(ops).find((op) => op.table === "trip_mute_prefs")?.row._deleted).toBe(true);
    expect(upserts(ops).find((op) => op.table === "profiles")?.row.display_name).toBe("Offline Test User");
    const meta = new Map(ops.filter((op) => "meta" in op).map((op) => [op.meta, op.value!]));
    expect(meta.get(ACTIVITY_SEEN)).toBe("2023-11-14T22:13:23.000000Z");
    const local = upserts(ops).filter((op) => op.table === "activity_log").map((op) => op.row);
    expect(local.some((state) => state._readAt === "2023-11-14T22:13:21.000000Z")).toBe(true);
    expect(local.some((state) => state._dismissedAt === "2023-11-14T22:13:22.000000Z")).toBe(true);
    expect(upserts(ops).filter((op) => op.table === "activity_log").every((op) => !!op.row.snapshot_json?.actor_name)).toBe(true);
  });

  it("retains soft deletes, removed people, hidden containers, shares and percentages", async () => {
    const rows = await fixtureRows();
    rows.ZTRIPENTITY[0]!.ZKIND = "non_group";
    rows.ZTRIPENTITY[0]!.ZMEMBERSIGNATURE = "fixture-signature";
    rows.ZEXPENSEENTITY[0]!.ZDELETEDAT = 1;
    rows.ZSETTLEMENTENTITY[0]!.ZDELETEDAT = 2;
    rows.ZTRIPPERSONENTITY[0]!.ZREMOVEDAT = 3;
    rows.ZEXPENSESPLITENTITY[0]!.ZSPLITTYPERAW = "percentage";
    rows.ZEXPENSESPLITENTITY[0]!.ZPERCENTAGE = "33.3300";
    rows.ZEXPENSESPLITENTITY[1]!.ZSPLITTYPERAW = "shares";
    rows.ZEXPENSESPLITENTITY[1]!.ZSHAREUNITS = "2.5000";
    const ops = upserts(convertLegacyRows(rows, userId));
    expect(ops.find((op) => op.table === "trips")?.row.kind).toBe("non_group");
    expect(ops.find((op) => op.table === "expenses")?.row.deleted_at).toBe("2001-01-01T00:00:01.000000Z");
    expect(ops.find((op) => op.table === "settlements")?.row.deleted_at).toBe("2001-01-01T00:00:02.000000Z");
    expect(ops.find((op) => op.table === "trip_people")?.row.removed_at).toBe("2001-01-01T00:00:03.000000Z");
    expect(ops.filter((op) => op.table === "expense_splits")[0]?.row.percentage).toBe("33.33");
    expect(ops.filter((op) => op.table === "expense_splits")[1]?.row.share_units).toBe("2.5");
  });

  it("rejects another account and broken required relationships", async () => {
    const rows = await fixtureRows();
    expect(() => convertLegacyRows(rows, "ffffffff-ffff-ffff-ffff-ffffffffffff")).toThrow(LegacyAccountMismatch);
    rows.ZEXPENSEENTITY[0]!.ZTRIP = 99999;
    expect(() => convertLegacyRows(rows, userId)).toThrow("Missing legacy relationship");
  });

  it("requires the native session owner when a cache has several profiles and no self-only cursor", async () => {
    const rows = await fixtureRows();
    rows.ZPROFILEENTITY[0]!.ZACTIVITYLASTSEENAT = null;
    rows.ZPROFILEENTITY.push({ ...rows.ZPROFILEENTITY[0]!, ZID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", Z_PK: 2 });
    expect(() => convertLegacyRows(rows, userId)).toThrow(LegacyAccountMismatch);
    expect(() => convertLegacyRows(rows, userId, { legacyUserId: userId })).not.toThrow();
    expect(() => convertLegacyRows(rows, userId, { legacyUserId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" })).toThrow(LegacyAccountMismatch);
  });

  it("merges legacy read/dismiss timestamps into an activity row already pulled by Expo", async () => {
    const incoming = convertLegacyRows(await fixtureRows(), userId);
    const activity = upserts(incoming).filter((op) => op.table === "activity_log").find((op) => op.row._readAt)!;
    const state = emptyState();
    (state.tables.activity_log as Map<string, typeof activity.row>).set(activity.row.id, { ...activity.row, _readAt: null });
    const selected = upserts(selectLegacyOps(state, incoming)).filter((op) => op.table === "activity_log");
    expect(selected.find((op) => op.row.id === activity.row.id)?.row._readAt).toBe(activity.row._readAt);
  });

  it("keeps newer Expo edits and their ledgers when import is retried", async () => {
    const incoming = convertLegacyRows(await fixtureRows(), userId);
    const expense = upserts(incoming).find((op) => op.table === "expenses")!;
    const state = emptyState();
    (state.tables.expenses as Map<string, typeof expense.row>).set(expense.row.id, {
      ...expense.row, description: "Edited in Expo", updated_at: "2099-01-01T00:00:00Z",
    });
    const selected = upserts(selectLegacyOps(state, incoming));
    expect(selected.some((op) => op.table === "expenses" && op.row.id === expense.row.id)).toBe(false);
    expect(selected.some((op) => (op.table === "expense_splits" || op.table === "expense_payments") && op.row.expense_id === expense.row.id)).toBe(false);
  });
});

describe("stored value encodings", () => {
  it("uses UUID bytes in their original order", () => {
    expect(legacyUUID(Uint8Array.from({ length: 16 }, (_, i) => i))).toBe("00010203-0405-0607-0809-0a0b0c0d0e0f");
    expect(() => legacyUUID(new Uint8Array(15))).toThrow();
  });

  it("keeps microseconds and dates on either side of the Apple epoch", () => {
    expect(legacyTimestamp(0)).toBe("2001-01-01T00:00:00.000000Z");
    expect(legacyTimestamp(-0.000001)).toBe("2000-12-31T23:59:59.999999Z");
    expect(legacyTimestamp(813989254.726537)).toBe("2026-10-18T04:07:34.726537Z");
    expect(() => legacyTimestamp(Infinity)).toThrow();
  });

  it("normalizes decimal text and scientific notation without JS money numbers", () => {
    expect(legacyDecimal("86.400")).toBe("86.4");
    expect(legacyDecimal("1.234e-5")).toBe("0.00001234");
    expect(legacyDecimal("999999999999.12345678")).toBe("999999999999.12345678");
    expect(() => legacyDecimal(86.4)).toThrow("SQL text");
    expect(() => legacyDecimal("12.5garbage")).toThrow();
  });

  it("selects numeric columns as text before SQLite crosses into JS", () => {
    const sql = legacySelect("ZEXPENSESPLITENTITY", ["Z_PK", "ZAMOUNTOWED", "ZSHAREUNITS", "ZPERCENTAGE"]);
    expect(sql).toContain('CAST("ZAMOUNTOWED" AS TEXT)');
    expect(sql).toContain('CAST("ZSHAREUNITS" AS TEXT)');
    expect(() => legacySelect("not-a-table", [])).toThrow();
  });

  it("recovers currency scale from a large REAL value without JS money numbers", async () => {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec("CREATE TABLE ZEXPENSEENTITY (ZAMOUNT DECIMAL)");
      db.prepare("INSERT INTO ZEXPENSEENTITY VALUES (?)").run("999999999999.999");
      const selected = db.prepare(legacySelect("ZEXPENSEENTITY", ["ZAMOUNT"])).get() as LegacyRow;
      const rows = await fixtureRows();
      rows.ZEXPENSEENTITY[0]!.ZAMOUNT = selected.ZAMOUNT!;
      rows.ZEXPENSEENTITY[0]!.ZCURRENCY = "BHD";
      const expense = upserts(convertLegacyRows(rows, userId)).find((op) => op.table === "expenses")!;
      expect(expense.row.amount).toBe("999999999999.999");
    } finally { db.close(); }
  });

  it("retains decimals for unknown currencies instead of assuming two minor-unit digits", async () => {
    const rows = await fixtureRows();
    rows.ZEXPENSEENTITY[0]!.ZCURRENCY = "ZZZ";
    rows.ZEXPENSEENTITY[0]!.ZAMOUNT = "1.23456789";
    const expense = upserts(convertLegacyRows(rows, userId)).find((op) => op.table === "expenses")!;
    expect(expense.row.amount).toBe("1.23456789");
  });

  it("reads pending seen dates from binary and XML UserDefaults", () => {
    const bytes = readFileSync(new URL("./fixtures/preferences.plist", import.meta.url));
    expect(pendingLegacyActivitySeen(bytes, userId)).toBe("2023-11-14T22:13:23.000000Z");
    expect(pendingLegacyActivitySeen(bytes, "other-account")).toBeNull();
    const xml = `<plist><dict><key>sync.pendingActivitySeenAt.${userId}</key><date>2023-11-14T22:13:23Z</date></dict></plist>`;
    expect(pendingLegacyActivitySeen(new TextEncoder().encode(xml), userId)).toBe("2023-11-14T22:13:23.000Z");
    expect(() => pendingLegacyActivitySeen(new TextEncoder().encode("bplist00"), userId)).toThrow();
  });

});
