import { beforeEach, expect, it, vi } from "vitest";

import { TABLE_NAMES, type State } from "./schema";
import type { Store } from "./store";
import { SyncEngine } from "./sync";

const mocks = vi.hoisted(() => ({
  calls: [] as string[],
  claim: vi.fn(),
  fetchSnapshot: vi.fn(),
}));

vi.mock("react-native", () => ({ AppState: { currentState: "active", addEventListener: vi.fn() } }));
vi.mock("expo-network", () => ({ addNetworkStateListener: vi.fn() }));
vi.mock("@/lib/ids", () => ({ uuid: () => "00000000-0000-0000-0000-000000000000" }));
vi.mock("./receipts", () => ({ uploadPendingReceipts: vi.fn() }));
vi.mock("./merge", () => ({ adoptServerPerson: vi.fn(), GONE: "gone", mergeRemote: () => [] }));
vi.mock("@/lib/supabase", () => ({
  supabase: {
    rpc: (name: string) => {
      mocks.calls.push(name);
      return name === "claim_trip_people_for_current_email" ? mocks.claim() : Promise.resolve({ data: null, error: null });
    },
  },
}));
vi.mock("./remote", async (original) => ({
  ...(await original<typeof import("./remote")>()),
  fetchSnapshot: (tripId?: string) => {
    mocks.calls.push(tripId ? `snapshot:${tripId}` : "snapshot");
    return mocks.fetchSnapshot();
  },
}));

function engine(rows: Partial<Record<(typeof TABLE_NAMES)[number], object[]>> = {}, commit = vi.fn(async (_ops: unknown[]) => {})) {
  const state: State = {
    tables: Object.fromEntries(
      TABLE_NAMES.map((t) => [t, new Map((rows[t] ?? []).map((row) => [(row as { id: string }).id, row]))]),
    ) as unknown as State["tables"],
    meta: new Map(),
  };
  const store = { getState: () => state, commit, subscribe: () => () => {} } as unknown as Store;
  return new SyncEngine(store, { id: "user", email: "me@x.test", displayName: "Me" });
}

beforeEach(() => {
  mocks.calls.length = 0;
  mocks.claim.mockResolvedValue({ data: [], error: null });
  mocks.fetchSnapshot.mockResolvedValue({ snapshot: {}, errors: [] });
});

it("claims trip people pending under the account's email before every full pull", async () => {
  const sync = engine();
  await sync.request({ pull: true });
  await sync.refresh();
  expect(mocks.calls.filter((c) => c === "claim_trip_people_for_current_email" || c === "snapshot")).toEqual([
    "claim_trip_people_for_current_email",
    "snapshot",
    "claim_trip_people_for_current_email",
    "snapshot",
  ]);
});

it("does not claim before a single trip's pull", async () => {
  await engine().request({ tripId: "trip" });
  expect(mocks.calls).toContain("snapshot:trip");
  expect(mocks.calls).not.toContain("claim_trip_people_for_current_email");
});

it("still pulls when the claim fails", async () => {
  mocks.claim.mockResolvedValue({ data: null, error: { message: "boom", code: "XX000" } });
  const sync = engine();
  await sync.request({ pull: true });
  expect(mocks.calls).toContain("snapshot");
  expect(sync.getStatus().phase).toBe("idle");
});

it("records a full pull, and counts a refused receipt photo as failed", async () => {
  const sync = engine({
    expenses: [{ id: "lunch", trip_id: "trip", write_id: "w1", _pushed: "w1", deleted_at: null, _receipt: "failed" }],
  });
  await sync.request();
  await sync.request({ tripId: "trip" });
  expect(sync.getStatus().lastSyncedAt).not.toBeNull();
  expect(sync.getStatus().lastPulledAt).toBeNull();
  expect(sync.getStatus()).toMatchObject({ pending: 1, failed: 1, phase: "error" });
  await sync.request({ pull: true });
  expect(sync.getStatus().lastPulledAt).not.toBeNull();
});

it("clears unsent rows under a deleted trip without sending them", async () => {
  const stamp = { write_id: "w1", updated_at: "2026-01-01T00:00:00Z", deleted_at: null };
  const edited = { id: "edited", trip_id: "trip", ...stamp, _pushed: "w0" };
  const commit = vi.fn(async (_ops: unknown[]) => {});
  const sync = engine(
    {
      trips: [{ id: "trip", kind: "trip", ...stamp, deleted_at: "2026-01-02T00:00:00Z", _pushed: "w1" }],
      trip_people: [{ id: "person", trip_id: "trip", user_id: null, removed_at: null, ...stamp, _pushed: null }],
      expenses: [{ id: "new", trip_id: "trip", ...stamp, _pushed: null }, edited],
      settlements: [{ id: "payment", trip_id: "trip", ...stamp, _pushed: null }],
    },
    commit,
  );
  await sync.request();
  expect(commit.mock.calls.map(([ops]) => ops)).toEqual([
    [{ table: "trip_people", key: "person", remove: true }],
    [{ table: "expenses", key: "new", remove: true }],
    [{ table: "expenses", row: { ...edited, _pushed: "w1", _error: null } }],
    [{ table: "settlements", key: "payment", remove: true }],
  ]);
  expect(mocks.calls).toEqual([]);
});

it("marks an expense whose person was discarded instead of leaving it waiting", async () => {
  const stamp = { write_id: "w1", updated_at: "2026-01-01T00:00:00Z", deleted_at: null };
  const expense = { id: "dinner", trip_id: "trip", ...stamp, _pushed: null };
  const commit = vi.fn(async (_ops: unknown[]) => {});
  const sync = engine(
    {
      trips: [{ id: "trip", kind: "trip", ...stamp, _pushed: "w1" }],
      expenses: [expense],
      expense_splits: [{ id: "dinner:ghost", expense_id: "dinner", trip_person_id: "ghost" }],
    },
    commit,
  );
  await sync.request();
  expect(commit.mock.calls.map(([ops]) => ops)).toEqual([
    [{ table: "expenses", row: { ...expense, _error: "Someone on this couldn't be added to the trip." } }],
  ]);
  expect(mocks.calls).toEqual([]);
});
