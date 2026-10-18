import { describe, expect, it } from "vitest";

import { mergeRemote, resolveConflict, type RemoteExpense } from "./merge";
import { rowKey, TABLE_NAMES, type Op, type State, type TableName, type Tables } from "./schema";
import { compareTimestamps, toMicros } from "./timestamps";

const USER = "11111111-1111-1111-1111-111111111111";
const TRIP = "aaaaaaaa-0000-0000-0000-000000000001";
const PERSON = "bbbbbbbb-0000-0000-0000-000000000001";
const OTHER = "bbbbbbbb-0000-0000-0000-000000000002";

function emptyState(): State {
  return { tables: Object.fromEntries(TABLE_NAMES.map((t) => [t, new Map()])) as unknown as State["tables"], meta: new Map() };
}

function withRows(state: State, rows: { [K in TableName]?: Tables[K][] }): State {
  const tables = { ...state.tables } as Record<TableName, Map<string, unknown>>;
  for (const [table, list] of Object.entries(rows) as [TableName, Tables[TableName][]][]) {
    const map = new Map(tables[table]);
    for (const row of list) map.set(rowKey(table, row as never), row);
    tables[table] = map;
  }
  return { tables: tables as unknown as State["tables"], meta: state.meta };
}

/** Applies ops the way the store does, for assertions. */
function apply(state: State, ops: Op[]): State {
  const tables = Object.fromEntries(TABLE_NAMES.map((t) => [t, new Map(state.tables[t] as Map<string, unknown>)])) as Record<
    TableName,
    Map<string, unknown>
  >;
  for (const op of ops) {
    if ("meta" in op) continue;
    if ("remove" in op) tables[op.table].delete(op.key);
    else tables[op.table].set(rowKey(op.table, op.row as never), op.row);
  }
  return { tables: tables as unknown as State["tables"], meta: state.meta };
}

const ctx = { userId: USER, now: new Date("2026-10-18T00:00:00Z"), normalizeAmount: (a: string) => a };

function trip(overrides: Partial<Tables["trips"]> = {}): Tables["trips"] {
  return {
    id: TRIP,
    name: "Lisbon",
    kind: "trip",
    member_signature: null,
    created_by: USER,
    last_activity_at: "2026-10-01T00:00:00Z",
    created_at: "2026-10-01T00:00:00Z",
    updated_at: "2026-10-01T00:00:00Z",
    deleted_at: null,
    write_id: "00000000-0000-0000-0000-000000000001",
    _pushed: "00000000-0000-0000-0000-000000000001",
    ...overrides,
  };
}

function expense(overrides: Partial<Tables["expenses"]> = {}): Tables["expenses"] {
  return {
    id: "eeeeeeee-0000-0000-0000-000000000001",
    trip_id: TRIP,
    amount: "30",
    currency: "EUR",
    category_id: null,
    description: "Dinner",
    expense_date: "2026-10-02",
    receipt_storage_path: null,
    payment_method: "card",
    created_by: USER,
    last_edited_by: null,
    created_at: "2026-10-02T00:00:00Z",
    updated_at: "2026-10-02T00:00:00Z",
    deleted_at: null,
    write_id: "00000000-0000-0000-0000-0000000000e1",
    _pushed: "00000000-0000-0000-0000-0000000000e1",
    ...overrides,
  };
}

function remoteExpense(e: Tables["expenses"], payers: string[], participants: string[]): RemoteExpense {
  const { _pushed, _error, _receipt, ...row } = e;
  void _pushed;
  void _error;
  void _receipt;
  const ledger = { expense_id: e.id, created_at: e.created_at, updated_at: e.updated_at, write_id: e.write_id };
  return {
    ...row,
    expense_payments: payers.map((p) => ({ ...ledger, trip_person_id: p, amount_paid: e.amount, payment_mode: "equal" as const })),
    expense_splits: participants.map((p) => ({
      ...ledger,
      trip_person_id: p,
      amount_owed: "15",
      split_type: "equal" as const,
      share_units: null,
      percentage: null,
    })),
  };
}

describe("timestamps", () => {
  it("orders microsecond timestamps exactly", () => {
    expect(compareTimestamps("2026-10-18T03:26:11.245123+00:00", "2026-10-18T03:26:11.245Z")).toBe(1);
    expect(compareTimestamps("2026-10-18T05:26:11.245+02:00", "2026-10-18T03:26:11.245Z")).toBe(0);
    expect(toMicros("2026-10-18T03:26:11Z") % 1_000_000n).toBe(0n);
  });
});

describe("resolveConflict", () => {
  const base = { updated_at: "2026-10-01T00:00:00Z", write_id: "b" };
  it("lets a delete beat a later live edit", () => {
    expect(resolveConflict({ ...base, updated_at: "2026-10-05T00:00:00Z" }, { ...base, write_id: "c", deleted_at: "2026-10-02T00:00:00Z" })).toBe("remote");
    expect(resolveConflict({ ...base, deleted_at: "2026-10-02T00:00:00Z" }, { ...base, write_id: "c", updated_at: "2026-10-09T00:00:00Z" })).toBe("local");
  });
  it("prefers the later write and breaks ties by write_id", () => {
    expect(resolveConflict(base, { ...base, write_id: "c", updated_at: "2026-10-02T00:00:00Z" })).toBe("remote");
    expect(resolveConflict(base, { ...base, write_id: "a" })).toBe("local");
    expect(resolveConflict(base, { ...base, write_id: "c" })).toBe("remote");
    expect(resolveConflict(base, base)).toBe("same");
  });
});

describe("mergeRemote", () => {
  it("adds new remote rows as clean", () => {
    const state = apply(emptyState(), mergeRemote(emptyState(), { trips: [trip()] }, ctx));
    expect(state.tables.trips.get(TRIP)?._pushed).toBe(trip().write_id);
  });

  it("keeps a newer offline edit and its ledgers", () => {
    const local = expense({ amount: "40", updated_at: "2026-10-03T00:00:00Z", write_id: "00000000-0000-0000-0000-0000000000e2" });
    let state = withRows(emptyState(), { trips: [trip()], expenses: [local] });
    state = withRows(state, {
      expense_splits: [
        { expense_id: local.id, trip_person_id: PERSON, amount_owed: "40", split_type: "equal", share_units: null, percentage: null, created_at: "x", updated_at: "x", write_id: "x" },
      ],
    });
    const next = apply(state, mergeRemote(state, { expenses: [remoteExpense(expense(), [PERSON], [PERSON, OTHER])] }, ctx));
    expect(next.tables.expenses.get(local.id)?.amount).toBe("40");
    expect([...next.tables.expense_splits.values()].map((s) => s.trip_person_id)).toEqual([PERSON]);
  });

  it("replaces a clean expense's ledgers with the server's", () => {
    const e = expense();
    let state = withRows(emptyState(), { trips: [trip()], expenses: [e] });
    state = withRows(state, {
      expense_splits: [
        { expense_id: e.id, trip_person_id: "gone", amount_owed: "30", split_type: "equal", share_units: null, percentage: null, created_at: "x", updated_at: "x", write_id: "x" },
      ],
    });
    const next = apply(state, mergeRemote(state, { expenses: [remoteExpense(e, [PERSON], [PERSON, OTHER])] }, ctx));
    expect([...next.tables.expense_splits.values()].map((s) => s.trip_person_id).sort()).toEqual([PERSON, OTHER].sort());
  });

  it("acknowledges a write the server already has", () => {
    const local = expense({ _pushed: null });
    const state = withRows(emptyState(), { trips: [trip()], expenses: [local] });
    const next = apply(state, mergeRemote(state, { expenses: [remoteExpense(expense(), [PERSON], [PERSON])] }, ctx));
    expect(next.tables.expenses.get(local.id)?._pushed).toBe(local.write_id);
  });

  it("removes rows the server no longer returns, with their children", () => {
    const e = expense();
    const state = withRows(emptyState(), { trips: [trip()], expenses: [e] });
    const next = apply(state, mergeRemote(state, { trips: [], expenses: [] }, ctx));
    expect(next.tables.trips.size).toBe(0);
    expect(next.tables.expenses.size).toBe(0);
  });

  it("keeps an unsent edit the server no longer has, marked for review", () => {
    const edited = expense({ write_id: "00000000-0000-0000-0000-0000000000e9" });
    const state = withRows(emptyState(), { trips: [trip()], expenses: [edited] });
    const next = apply(state, mergeRemote(state, { trips: [], expenses: [] }, ctx));
    expect(next.tables.expenses.get(edited.id)?._error).toBeTruthy();
    expect(next.tables.trips.get(TRIP)?._error).toBeTruthy();
  });

  it("never removes rows that haven't reached the server", () => {
    const fresh = trip({ _pushed: null });
    const state = withRows(emptyState(), { trips: [fresh] });
    const next = apply(state, mergeRemote(state, { trips: [] }, ctx));
    expect(next.tables.trips.get(TRIP)).toBeDefined();
  });

  it("skips removals for a table whose pull failed", () => {
    const state = withRows(emptyState(), { trips: [trip()], expenses: [expense()] });
    const next = apply(state, mergeRemote(state, { trips: [trip()] }, ctx));
    expect(next.tables.expenses.size).toBe(1);
  });

  it("limits removals to the pulled trip", () => {
    const otherTrip = trip({ id: "aaaaaaaa-0000-0000-0000-000000000002" });
    const state = withRows(emptyState(), { trips: [trip(), otherTrip] });
    const next = apply(state, mergeRemote(state, { trips: [trip()], expenses: [] }, { ...ctx, tripId: TRIP }));
    expect(next.tables.trips.size).toBe(2);
  });

  it("shows server activity time on a trip with a pending rename", () => {
    const local = trip({ name: "Porto", write_id: "00000000-0000-0000-0000-000000000009", updated_at: "2026-10-09T00:00:00Z" });
    const state = withRows(emptyState(), { trips: [local] });
    const next = apply(state, mergeRemote(state, { trips: [trip({ last_activity_at: "2026-10-10T00:00:00Z" })] }, ctx));
    expect(next.tables.trips.get(TRIP)?.name).toBe("Porto");
    expect(next.tables.trips.get(TRIP)?.last_activity_at).toBe("2026-10-10T00:00:00Z");
  });

  it("drops activity outside the window", () => {
    const state = withRows(emptyState(), {
      trips: [trip()],
      activity_log: [
        { id: "old", trip_id: TRIP, actor_id: USER, action: "trip_created", entity_type: "trip", entity_id: TRIP, timestamp: "2026-01-01T00:00:00Z", snapshot_json: null },
      ],
    });
    const next = apply(state, mergeRemote(state, { trips: [trip()], activity_log: [] }, ctx));
    expect(next.tables.activity_log.size).toBe(0);
  });
});
