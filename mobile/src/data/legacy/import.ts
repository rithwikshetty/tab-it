import { Directory, File, Paths } from "expo-file-system";
import * as SQLite from "expo-sqlite";
import { Platform } from "react-native";

import type { Op } from "../schema";
import type { Store } from "../store";
import { ACTIVITY_SEEN, IMPORT_MARKER, LegacyAccountMismatch, convertLegacyRows, legacyUUID, selectLegacyOps } from "./convert";
import { pendingLegacyActivitySeen } from "./preferences";
import { readLegacyRows } from "./reader";

export interface LegacyImportResult {
  status: "imported" | "already-imported" | "not-found" | "unsupported" | "account-mismatch" | "failed";
  rows: number;
  archived: boolean;
}

export interface LegacyImportOptions {
  legacyUserId?: string;
}

const ARCHIVE_SUFFIX = ".expo-imported-v1";
const inFlight = new WeakMap<Store, Promise<LegacyImportResult>>();
const failedStores = new WeakSet<Store>();

function locations() {
  const support = new Directory(Paths.document.parentDirectory, "Library", "Application Support");
  return {
    support,
    source: new File(support, "default.store"),
    receiptSource: new Directory(support, "ReceiptUploads"),
    receiptTarget: new Directory(Paths.document, "receipts"),
    preferences: new File(Paths.document.parentDirectory, "Library", "Preferences", "com.rithwikshetty.tab.plist"),
  };
}

async function archiveStore(source: File): Promise<boolean> {
  const archive = new File(`${source.uri}${ARCHIVE_SUFFIX}`);
  for (const suffix of ["-wal", "-shm", ""] as const) {
    const file = new File(`${source.uri}${suffix}`);
    const target = new File(`${archive.uri}${suffix}`);
    if (!file.exists) continue;
    if (target.exists) return false;
    await file.move(target);
  }
  return archive.exists && !source.exists;
}

function receiptFiles(dir: Directory): Map<string, File> {
  const files = new Map<string, File>();
  if (!dir.exists) return files;
  for (const file of dir.list()) {
    if (!(file instanceof File)) continue;
    const match = /^([a-f0-9-]{36})__([a-f0-9-]{36})\.jpg$/i.exec(file.name);
    if (!match) continue;
    const tripId = legacyUUID(match[1]!);
    const expenseId = legacyUUID(match[2]!);
    files.set(`${tripId}/${expenseId}.jpg`, file);
  }
  return files;
}

async function finishReceipts(source: Directory, files: readonly File[]): Promise<void> {
  if (!files.length) return;
  const archive = new Directory(source.parentDirectory, `ReceiptUploads${ARCHIVE_SUFFIX}`);
  archive.create({ intermediates: true, idempotent: true });
  for (const file of files) {
    if (!file.exists) continue;
    const target = new File(archive, file.name);
    if (!target.exists) await file.move(target);
  }
}

async function runImport(store: Store, userId: string, options: LegacyImportOptions): Promise<LegacyImportResult> {
  const result = (status: LegacyImportResult["status"], rows = 0, archived = false): LegacyImportResult => ({ status, rows, archived });
  if (Platform.OS !== "ios") return result("unsupported");
  if (legacyUUID(store.userId) !== legacyUUID(userId)) return result("account-mismatch");
  if (options.legacyUserId && legacyUUID(options.legacyUserId) !== legacyUUID(userId)) return result("account-mismatch");
  if (failedStores.has(store)) return result("failed");
  const paths = locations();
  if (store.getState().meta.has(IMPORT_MARKER)) {
    let archived = false;
    try { archived = await archiveStore(paths.source); } catch { console.warn("[legacy] Import is saved; the legacy store could not be archived."); }
    return result("already-imported", 0, archived);
  }
  if (!paths.source.exists) return result("not-found");

  const scratch = new Directory(Paths.cache, `legacy-import-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  scratch.create({ intermediates: true });
  let db: SQLite.SQLiteDatabase | null = null;
  try {
    for (const suffix of ["", "-wal"] as const) {
      const file = new File(`${paths.source.uri}${suffix}`);
      if (file.exists) await file.copy(new File(scratch, `default.store${suffix}`));
    }
    db = await SQLite.openDatabaseAsync("default.store", { useNewConnection: true }, scratch.uri);
    await db.execAsync("PRAGMA query_only = ON; BEGIN DEFERRED TRANSACTION;");
    const check = await db.getFirstAsync<{ quick_check: string }>("PRAGMA quick_check");
    if (check?.quick_check !== "ok") throw new Error("Legacy database integrity check failed");
    const rows = await readLegacyRows(db);
    await db.execAsync("ROLLBACK");
    await db.closeAsync();
    db = null;

    const pending = receiptFiles(paths.receiptSource);
    const pendingSeen = paths.preferences.exists
      ? pendingLegacyActivitySeen(await paths.preferences.bytes(), userId)
      : null;
    const converted = convertLegacyRows(rows, userId, {
      pendingReceiptPaths: new Set(pending.keys()), pendingActivitySeenAt: pendingSeen, legacyUserId: options.legacyUserId,
    });
    const ops = selectLegacyOps(store.getState(), converted);
    const staged: File[] = [];
    for (const op of ops) {
      if (!("table" in op) || op.table !== "expenses" || !("row" in op) || op.row._receipt !== "pending") continue;
      const path = op.row.receipt_storage_path;
      const source = path ? pending.get(path) : undefined;
      if (!source) throw new Error("Missing legacy receipt");
      paths.receiptTarget.create({ intermediates: true, idempotent: true });
      const target = new File(paths.receiptTarget, path!.replace("/", "__"));
      if (!target.exists) {
        const temporary = new File(`${target.uri}.legacy-v1`);
        await source.copy(temporary, { overwrite: true });
        if (temporary.size !== source.size) throw new Error("Incomplete legacy receipt copy");
        await temporary.move(target);
      } else {
        const [left, right] = await Promise.all([source.bytes(), target.bytes()]);
        if (left.length !== right.length || left.some((value, i) => value !== right[i])) {
          throw new Error("A different pending receipt already exists");
        }
      }
      staged.push(source);
    }
    const importedRows = ops.filter((op) => "row" in op).length;
    const marker: Op = { meta: IMPORT_MARKER, value: JSON.stringify({ userId: legacyUUID(userId), rows: importedRows, importedAt: new Date().toISOString() }) };
    try {
      await store.commit([...ops, marker]);
      await store.flush();
      if (store.getState().meta.get(IMPORT_MARKER) !== marker.value) throw new Error("The destination store closed during import");
    } catch {
      failedStores.add(store);
      throw new Error("Legacy data could not be persisted; restart before retrying");
    }
    let archived = false;
    try {
      archived = await archiveStore(paths.source);
      await finishReceipts(paths.receiptSource, staged);
    } catch {
      console.warn("[legacy] Import is saved; some legacy files could not be archived.");
    }
    return result("imported", importedRows, archived);
  } finally {
    try { await db?.closeAsync(); } catch { console.warn("[legacy] Could not close the temporary database."); }
    try { if (scratch.exists) scratch.delete(); } catch { console.warn("[legacy] Could not remove the temporary database copy."); }
  }
}

export function importLegacyData(store: Store, userId: string, options: LegacyImportOptions = {}): Promise<LegacyImportResult> {
  const running = inFlight.get(store);
  if (running) return running;
  const promise = runImport(store, userId, options).catch((error: unknown): LegacyImportResult => {
    const mismatch = error instanceof LegacyAccountMismatch;
    console.warn(mismatch
      ? "[legacy] Could not confirm the legacy account; its files were retained."
      : "[legacy] Import did not complete; legacy data and receipt originals were retained.");
    return { status: mismatch ? "account-mismatch" : "failed", rows: 0, archived: false };
  }).finally(() => inFlight.delete(store));
  inFlight.set(store, promise);
  return promise;
}

export { ACTIVITY_SEEN };
