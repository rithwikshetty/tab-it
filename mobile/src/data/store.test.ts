import { mkdtempSync, rmSync } from "node:fs";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

const runtime = vi.hoisted(() => ({ root: "", failTransactions: 0 }));

vi.mock("expo-sqlite", async () => {
  const { DatabaseSync } = await import("node:sqlite");
  const { join } = await import("node:path");
  type Param = string | number | null;
  async function openDatabaseAsync(name: string) {
    const db = new DatabaseSync(join(runtime.root, name));
    const adapter = {
      async execAsync(sql: string) {
        db.exec(sql);
      },
      async getAllAsync<T>(sql: string, ...params: Param[]) {
        return db.prepare(sql).all(...params) as T[];
      },
      async getFirstAsync<T>(sql: string, ...params: Param[]) {
        return db.prepare(sql).get(...params) as T | undefined;
      },
      async runAsync(sql: string, ...params: Param[]) {
        return db.prepare(sql).run(...params);
      },
      async withExclusiveTransactionAsync(work: (tx: { runAsync(sql: string, ...params: Param[]): Promise<unknown> }) => Promise<void>) {
        db.exec("BEGIN");
        try {
          await work(adapter);
          if (runtime.failTransactions > 0) {
            runtime.failTransactions--;
            throw new Error("Injected disk failure");
          }
          db.exec("COMMIT");
        } catch (error) {
          db.exec("ROLLBACK");
          throw error;
        }
      },
      async closeAsync() {
        db.close();
      },
    };
    return adapter;
  }
  return { openDatabaseAsync };
});

import { openStore, type Store } from "./store";
import type { LocalTrip } from "./schema";

const userId = "11111111-1111-1111-1111-111111111111";
let store: Store;

function trip(id: string, name: string): LocalTrip {
  return {
    id,
    name,
    created_by: userId,
    created_at: "2026-10-18T00:00:00Z",
    updated_at: "2026-10-18T00:00:00Z",
    deleted_at: null,
    write_id: `${name}-write`,
    _pushed: null,
    _error: null,
  } as LocalTrip;
}

beforeEach(async () => {
  runtime.root = mkdtempSync("/tmp/tab-store-test-");
  runtime.failTransactions = 0;
  vi.spyOn(console, "error").mockImplementation(() => undefined);
  store = await openStore(userId);
});

afterEach(async () => {
  await store.close();
  rmSync(runtime.root, { recursive: true, force: true });
  vi.restoreAllMocks();
});

test("a failed write puts memory back to what is on disk", async () => {
  await store.commit([
    { table: "trips", row: trip("a", "Saved") },
    { meta: "cursor", value: "1" },
  ]);
  runtime.failTransactions = 1;
  const failed = store.commit([
    { table: "trips", row: trip("a", "Unsaved") },
    { table: "trips", row: trip("b", "New") },
    { table: "trips", key: "a", remove: true },
    { meta: "cursor", value: "2" },
  ]);
  expect(store.getState().tables.trips.has("b")).toBe(true);
  await expect(failed).rejects.toThrow("Injected disk failure");
  const state = store.getState();
  expect(state.tables.trips.get("a")?.name).toBe("Saved");
  expect(state.tables.trips.has("b")).toBe(false);
  expect(state.meta.get("cursor")).toBe("1");
});

test("a key changed again after the failed write keeps its newer value", async () => {
  runtime.failTransactions = 1;
  const failed = store.commit([{ table: "trips", row: trip("a", "First") }]);
  const later = store.commit([{ table: "trips", row: trip("a", "Second") }]);
  await expect(failed).rejects.toThrow();
  await later;
  expect(store.getState().tables.trips.get("a")?.name).toBe("Second");
  await store.close();
  store = await openStore(userId);
  expect(store.getState().tables.trips.get("a")?.name).toBe("Second");
});
