import * as SQLite from "expo-sqlite";

import { rowKey, TABLE_NAMES, type Op, type State, type TableMaps, type TableName, type Tables } from "./schema";

// The local store is the app's single source of truth for everything the UI
// shows. Every row lives in memory (a signed-in user's data is small) and is
// mirrored to a per-user SQLite file so the app opens instantly and works
// offline. A commit updates memory synchronously, notifies subscribers, and
// persists in one SQLite transaction.

export interface Store {
  readonly userId: string;
  getState(): State;
  subscribe(listener: () => void): () => void;
  commit(ops: readonly Op[]): Promise<void>;
  /** Waits for every pending write to reach disk. */
  flush(): Promise<void>;
  close(): Promise<void>;
}

const SCHEMA = `
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS rows (
  tbl  TEXT NOT NULL,
  key  TEXT NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (tbl, key)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
`;

export function databaseName(userId: string): string {
  return `tab-${userId}.db`;
}

export async function openStore(userId: string): Promise<Store> {
  const db = await SQLite.openDatabaseAsync(databaseName(userId));
  await db.execAsync(SCHEMA);

  const maps = Object.fromEntries(TABLE_NAMES.map((t) => [t, new Map()])) as {
    [K in TableName]: Map<string, Tables[K]>;
  };
  for (const r of await db.getAllAsync<{ tbl: string; key: string; json: string }>("SELECT tbl, key, json FROM rows")) {
    const map = maps[r.tbl as TableName] as Map<string, unknown> | undefined;
    map?.set(r.key, JSON.parse(r.json));
  }
  const meta = new Map<string, string>();
  for (const r of await db.getAllAsync<{ key: string; value: string }>("SELECT key, value FROM meta")) {
    meta.set(r.key, r.value);
  }

  let state: State = { tables: maps, meta };
  const listeners = new Set<() => void>();
  let writes: Promise<void> = Promise.resolve();
  let closed = false;

  function commit(ops: readonly Op[]): Promise<void> {
    if (closed || ops.length === 0) return writes;
    const nextTables: Partial<Record<TableName, Map<string, unknown>>> = {};
    let nextMeta: Map<string, string> | null = null;
    const upserts: [string, string, string][] = [];
    const removals: [string, string][] = [];
    const metaWrites: [string, string | null][] = [];

    const tableFor = (t: TableName) => (nextTables[t] ??= new Map(state.tables[t] as Map<string, unknown>));

    for (const op of ops) {
      if ("meta" in op) {
        nextMeta ??= new Map(state.meta);
        if (op.value === null) nextMeta.delete(op.meta);
        else nextMeta.set(op.meta, op.value);
        metaWrites.push([op.meta, op.value]);
      } else if ("remove" in op) {
        if (!(nextTables[op.table] ?? state.tables[op.table]).has(op.key)) continue;
        tableFor(op.table).delete(op.key);
        removals.push([op.table, op.key]);
      } else {
        const key = rowKey(op.table, op.row as never);
        const json = JSON.stringify(op.row);
        const current = (nextTables[op.table] ?? state.tables[op.table]).get(key);
        if (current !== undefined && JSON.stringify(current) === json) continue;
        tableFor(op.table).set(key, op.row);
        upserts.push([op.table, key, json]);
      }
    }

    if (upserts.length === 0 && removals.length === 0 && metaWrites.length === 0) return writes;
    state = {
      tables: { ...state.tables, ...nextTables } as TableMaps,
      meta: nextMeta ?? state.meta,
    };
    for (const listener of listeners) listener();

    writes = writes.then(() =>
      db.withExclusiveTransactionAsync(async (tx) => {
        for (const [tbl, key, json] of upserts) {
          await tx.runAsync("INSERT OR REPLACE INTO rows (tbl, key, json) VALUES (?, ?, ?)", tbl, key, json);
        }
        for (const [tbl, key] of removals) {
          await tx.runAsync("DELETE FROM rows WHERE tbl = ? AND key = ?", tbl, key);
        }
        for (const [key, value] of metaWrites) {
          if (value === null) await tx.runAsync("DELETE FROM meta WHERE key = ?", key);
          else await tx.runAsync("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", key, value);
        }
      }),
    );
    // A failed write rejects this commit's promise so the caller can say so,
    // but doesn't poison the queue for later commits.
    const result = writes;
    writes = writes.catch((error: unknown) => {
      console.error("[store] persist failed", error);
    });
    return result;
  }

  return {
    userId,
    getState: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    commit,
    flush: () => writes,
    async close() {
      if (closed) return;
      closed = true;
      await writes;
      listeners.clear();
      await db.closeAsync();
    },
  };
}

/** Removes a user's local database, used on sign-out and account deletion. */
export async function deleteStore(userId: string): Promise<void> {
  try {
    await SQLite.deleteDatabaseAsync(databaseName(userId));
  } catch {
    // Already gone.
  }
}
