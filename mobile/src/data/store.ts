import * as SQLite from "expo-sqlite";

import { rowKey, TABLE_NAMES, type Op, type State, type TableMaps, type TableName, type Tables } from "./schema";

// The local store is the app's single source of truth for everything the UI
// shows. Every row lives in memory (a signed-in user's data is small) and is
// mirrored to a per-user SQLite file so the app opens instantly and works
// offline. A commit updates memory synchronously, notifies subscribers, and
// persists in one SQLite transaction. If that transaction fails, memory goes
// back to what is on disk, so nothing can sync or build on a change the phone
// never saved.

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
    // The final state of every touched key, so a remove followed by a re-add
    // of the same key lands on disk exactly as it does in memory.
    const rowWrites = new Map<string, { tbl: TableName; key: string; json: string | null; value: unknown }>();
    const metaWrites = new Map<string, string | null>();

    const tableFor = (t: TableName) => (nextTables[t] ??= new Map(state.tables[t] as Map<string, unknown>));

    for (const op of ops) {
      if ("meta" in op) {
        nextMeta ??= new Map(state.meta);
        if (op.value === null) nextMeta.delete(op.meta);
        else nextMeta.set(op.meta, op.value);
        metaWrites.set(op.meta, op.value);
      } else if ("remove" in op) {
        if (!(nextTables[op.table] ?? state.tables[op.table]).has(op.key)) continue;
        tableFor(op.table).delete(op.key);
        rowWrites.set(`${op.table}\u0000${op.key}`, { tbl: op.table, key: op.key, json: null, value: undefined });
      } else {
        const key = rowKey(op.table, op.row as never);
        const json = JSON.stringify(op.row);
        const current = (nextTables[op.table] ?? state.tables[op.table]).get(key);
        if (current !== undefined && JSON.stringify(current) === json) continue;
        tableFor(op.table).set(key, op.row);
        rowWrites.set(`${op.table}\u0000${key}`, { tbl: op.table, key, json, value: op.row });
      }
    }

    if (rowWrites.size === 0 && metaWrites.size === 0) return writes;
    state = {
      tables: { ...state.tables, ...nextTables } as TableMaps,
      meta: nextMeta ?? state.meta,
    };
    for (const listener of listeners) listener();

    const persisted = writes.then(() =>
      db.withExclusiveTransactionAsync(async (tx) => {
        for (const { tbl, key, json } of rowWrites.values()) {
          if (json === null) await tx.runAsync("DELETE FROM rows WHERE tbl = ? AND key = ?", tbl, key);
          else await tx.runAsync("INSERT OR REPLACE INTO rows (tbl, key, json) VALUES (?, ?, ?)", tbl, key, json);
        }
        for (const [key, value] of metaWrites) {
          if (value === null) await tx.runAsync("DELETE FROM meta WHERE key = ?", key);
          else await tx.runAsync("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", key, value);
        }
      }),
    );
    // A failed write rejects this commit's promise so the caller can say so,
    // but doesn't poison the queue for later commits.
    const result = persisted.catch(async (error: unknown) => {
      console.error("[store] persist failed", error);
      await restoreFromDisk(rowWrites.values(), metaWrites).catch((e: unknown) => console.error("[store] restore failed", e));
      throw error;
    });
    writes = result.catch(() => undefined);
    return result;
  }

  /**
   * Puts the keys a failed commit touched back to their saved values. A key a
   * later commit has changed again is left alone; that commit saves it.
   */
  async function restoreFromDisk(rows: Iterable<{ tbl: TableName; key: string; value: unknown }>, metas: Map<string, string | null>) {
    const saved: { tbl: TableName; key: string; value: unknown; disk: unknown }[] = [];
    for (const w of rows) {
      const r = await db.getFirstAsync<{ json: string }>("SELECT json FROM rows WHERE tbl = ? AND key = ?", w.tbl, w.key);
      saved.push({ ...w, disk: r ? JSON.parse(r.json) : undefined });
    }
    const savedMeta: { key: string; value: string | null; disk: string | null }[] = [];
    for (const [key, value] of metas) {
      const r = await db.getFirstAsync<{ value: string }>("SELECT value FROM meta WHERE key = ?", key);
      savedMeta.push({ key, value, disk: r?.value ?? null });
    }
    const nextTables: Partial<Record<TableName, Map<string, unknown>>> = {};
    let nextMeta: Map<string, string> | null = null;
    for (const w of saved) {
      if ((state.tables[w.tbl] as Map<string, unknown>).get(w.key) !== w.value) continue;
      const map = (nextTables[w.tbl] ??= new Map(state.tables[w.tbl] as Map<string, unknown>));
      if (w.disk === undefined) map.delete(w.key);
      else map.set(w.key, w.disk);
    }
    for (const m of savedMeta) {
      if ((state.meta.get(m.key) ?? null) !== m.value) continue;
      nextMeta ??= new Map(state.meta);
      if (m.disk === null) nextMeta.delete(m.key);
      else nextMeta.set(m.key, m.disk);
    }
    if (Object.keys(nextTables).length === 0 && !nextMeta) return;
    state = { tables: { ...state.tables, ...nextTables } as TableMaps, meta: nextMeta ?? state.meta };
    for (const listener of listeners) listener();
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
