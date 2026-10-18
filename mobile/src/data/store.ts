import * as SQLite from "expo-sqlite";

import { rowKey, TABLE_NAMES, type Op, type State, type TableMaps, type TableName, type Tables } from "./schema";

// The local store is the app's single source of truth for everything the UI
// shows. Every row lives in memory (a signed-in user's data is small) and is
// mirrored to a per-user SQLite file so the app opens instantly and works
// offline. A commit updates memory synchronously, notifies subscribers, and
// persists in one SQLite transaction, in commit order.
//
// If a transaction fails, memory is reloaded from disk, and every commit made
// before that reload finished fails too: any of them may build on the change
// that wasn't saved. So nothing can sync, or be partly saved, on top of a
// change the phone never stored.

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

/** Rejects a commit that was queued behind one that failed to save. */
class EarlierWriteFailed extends Error {
  constructor() {
    super("An earlier change couldn't be saved on this phone.");
  }
}

export function databaseName(userId: string): string {
  return `tab-${userId}.db`;
}

async function load(db: SQLite.SQLiteDatabase): Promise<State> {
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
  return { tables: maps, meta };
}

export async function openStore(userId: string): Promise<Store> {
  const db = await SQLite.openDatabaseAsync(databaseName(userId));
  await db.execAsync(SCHEMA);

  let state = await load(db);
  const listeners = new Set<() => void>();
  let writes: Promise<void> = Promise.resolve();
  let closed = false;
  // Bumped when a write fails and again once memory is reloaded; a commit from
  // an older generation was made before the reload and must not save.
  let generation = 0;

  function commit(ops: readonly Op[]): Promise<void> {
    if (closed) return writes;
    const gen = generation;
    const nextTables: Partial<Record<TableName, Map<string, unknown>>> = {};
    let nextMeta: Map<string, string> | null = null;
    // The final state of every touched key, so a remove followed by a re-add
    // of the same key lands on disk exactly as it does in memory.
    const rowWrites = new Map<string, { tbl: TableName; key: string; json: string | null }>();
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
        rowWrites.set(`${op.table}\u0000${op.key}`, { tbl: op.table, key: op.key, json: null });
      } else {
        const key = rowKey(op.table, op.row as never);
        const json = JSON.stringify(op.row);
        const current = (nextTables[op.table] ?? state.tables[op.table]).get(key);
        if (current !== undefined && JSON.stringify(current) === json) continue;
        tableFor(op.table).set(key, op.row);
        rowWrites.set(`${op.table}\u0000${key}`, { tbl: op.table, key, json });
      }
    }

    if (rowWrites.size > 0 || metaWrites.size > 0) {
      state = {
        tables: { ...state.tables, ...nextTables } as TableMaps,
        meta: nextMeta ?? state.meta,
      };
      for (const listener of listeners) listener();
    }

    // Even a commit that changed nothing waits its turn: what it saw may rest
    // on an earlier change that hasn't saved yet.
    const persisted = writes.then(async () => {
      if (gen !== generation) throw new EarlierWriteFailed();
      if (rowWrites.size === 0 && metaWrites.size === 0) return;
      await db.withExclusiveTransactionAsync(async (tx) => {
        for (const { tbl, key, json } of rowWrites.values()) {
          if (json === null) await tx.runAsync("DELETE FROM rows WHERE tbl = ? AND key = ?", tbl, key);
          else await tx.runAsync("INSERT OR REPLACE INTO rows (tbl, key, json) VALUES (?, ?, ?)", tbl, key, json);
        }
        for (const [key, value] of metaWrites) {
          if (value === null) await tx.runAsync("DELETE FROM meta WHERE key = ?", key);
          else await tx.runAsync("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", key, value);
        }
      });
    });
    const result = persisted.catch(async (error: unknown) => {
      if (!(error instanceof EarlierWriteFailed)) {
        console.error("[store] persist failed", error);
        generation++;
        try {
          state = await load(db);
          for (const listener of listeners) listener();
        } catch (e) {
          console.error("[store] reload failed", e);
        }
        generation++;
      }
      throw error;
    });
    // A failure rejects its own commit and those queued behind it, then the
    // queue carries on for later commits.
    writes = result.catch(() => undefined);
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
