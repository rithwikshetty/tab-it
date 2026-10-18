import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const runtime = vi.hoisted(() => ({
  root: "", platform: "ios", failWrites: false, failArchive: false,
  opens: [] as string[],
}));

vi.mock("react-native", () => ({ Platform: { get OS() { return runtime.platform; } } }));

vi.mock("expo-file-system", async () => {
  const fs = await import("node:fs");
  const path = await import("node:path");
  const { fileURLToPath, pathToFileURL } = await import("node:url");
  function location(parts: (string | { uri: string })[]) {
    return path.join(...parts.map((p) => {
      const value = typeof p === "string" ? p : p.uri;
      return value.startsWith("file:") ? fileURLToPath(value) : value;
    }));
  }
  class Directory {
    path: string;
    constructor(...parts: (string | { uri: string })[]) { this.path = location(parts); }
    get uri() { return pathToFileURL(this.path).href; }
    get exists() { return fs.existsSync(this.path); }
    get parentDirectory() { return new Directory(path.dirname(this.path)); }
    create() { fs.mkdirSync(this.path, { recursive: true }); }
    delete() { fs.rmSync(this.path, { recursive: true }); }
    list() { return fs.readdirSync(this.path, { withFileTypes: true }).map((p) => p.isDirectory() ? new Directory(this.path, p.name) : new File(this.path, p.name)); }
  }
  class File {
    path: string;
    constructor(...parts: (string | { uri: string })[]) { this.path = location(parts); }
    get uri() { return pathToFileURL(this.path).href; }
    get name() { return path.basename(this.path); }
    get exists() { return fs.existsSync(this.path); }
    get size() { return fs.statSync(this.path).size; }
    async bytes() { return fs.readFileSync(this.path); }
    async copy(target: File, options?: { overwrite?: boolean }) {
      fs.copyFileSync(this.path, target.path, options?.overwrite ? 0 : fs.constants.COPYFILE_EXCL);
    }
    async move(target: File) {
      if (runtime.failArchive && this.name === "default.store") throw new Error("Injected archive failure");
      if (target.exists) throw new Error("Target exists");
      fs.renameSync(this.path, target.path);
      this.path = target.path;
    }
  }
  return { Directory, File, Paths: {
    get document() { return new Directory(runtime.root, "Documents"); },
    get cache() { return new Directory(runtime.root, "Library", "Caches"); },
  } };
});

vi.mock("expo-sqlite", async () => {
  const { DatabaseSync } = await import("node:sqlite");
  const { join } = await import("node:path");
  const { mkdirSync } = await import("node:fs");
  const { fileURLToPath } = await import("node:url");
  async function openDatabaseAsync(name: string, _options?: unknown, directory?: string) {
    const dir = directory?.startsWith("file:") ? fileURLToPath(directory) : directory ?? join(runtime.root, "Library", "SQLite");
    mkdirSync(dir, { recursive: true });
    const filename = join(dir, name);
    runtime.opens.push(filename);
    const db = new DatabaseSync(filename);
    const adapter = {
      async execAsync(sql: string) { db.exec(sql); },
      async getAllAsync<T>(sql: string) { return db.prepare(sql).all() as T[]; },
      async getFirstAsync<T>(sql: string) { return db.prepare(sql).get() as T | undefined; },
      async runAsync(sql: string, ...params: (string | number | null)[]) { return db.prepare(sql).run(...params); },
      async withExclusiveTransactionAsync(work: (tx: { runAsync(sql: string, ...params: (string | number | null)[]): Promise<unknown> }) => Promise<void>) {
        if (runtime.failWrites) throw new Error("Injected disk failure");
        db.exec("BEGIN");
        try { await work(adapter); db.exec("COMMIT"); } catch (error) { db.exec("ROLLBACK"); throw error; }
      },
      async closeAsync() { db.close(); },
    };
    return adapter;
  }
  return { openDatabaseAsync };
});

import { openStore, type Store } from "../store";
import { IMPORT_MARKER } from "./convert";
import { importLegacyData } from "./import";

const userId = "11111111-1111-1111-1111-111111111111";
const fixtures = fileURLToPath(new URL("./fixtures", import.meta.url));
let store: Store | null = null;
let warn: ReturnType<typeof vi.spyOn>;

function sourcePath() { return join(runtime.root, "Library", "Application Support", "default.store"); }

function installFixture() {
  const support = join(runtime.root, "Library", "Application Support");
  mkdirSync(join(support, "ReceiptUploads"), { recursive: true });
  mkdirSync(join(runtime.root, "Library", "Preferences"), { recursive: true });
  copyFileSync(join(fixtures, "default.store"), sourcePath());
  copyFileSync(join(fixtures, "preferences.plist"), join(runtime.root, "Library", "Preferences", "com.rithwikshetty.tab.plist"));
  for (const name of readdirSync(fixtures).filter((name) => name.endsWith(".jpg"))) {
    copyFileSync(join(fixtures, name), join(support, "ReceiptUploads", name));
  }
}

beforeEach(() => {
  runtime.root = mkdtempSync("/tmp/tab-legacy-test-");
  runtime.platform = "ios";
  runtime.failWrites = false;
  runtime.failArchive = false;
  runtime.opens.length = 0;
  mkdirSync(join(runtime.root, "Documents"));
  warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
  vi.spyOn(console, "error").mockImplementation(() => undefined);
});

afterEach(async () => {
  await store?.close();
  store = null;
  rmSync(runtime.root, { recursive: true, force: true });
  vi.restoreAllMocks();
});

describe("in-place upgrade import", () => {
  it("durably imports data and receipt bytes, then renames the old store", async () => {
    installFixture();
    const original = readFileSync(sourcePath());
    store = await openStore(userId);
    const outcome = await importLegacyData(store, userId);
    expect(outcome).toMatchObject({ status: "imported", archived: true });
    expect(outcome.rows).toBeGreaterThan(95);
    expect(existsSync(sourcePath())).toBe(false);
    expect(readFileSync(sourcePath() + ".expo-imported-v1")).toEqual(original);
    expect(runtime.opens).not.toContain(sourcePath());
    expect(runtime.opens.some((p) => p.includes("legacy-import-") && p.endsWith("default.store"))).toBe(true);
    const state = store.getState();
    expect(state.tables.trips.size).toBe(3);
    expect(state.tables.expenses.size).toBe(12);
    expect(state.tables.expense_splits.size).toBe(49);
    expect(state.meta.has(IMPORT_MARKER)).toBe(true);
    expect([...state.tables.activity_log.values()].filter((a) => a._readAt || a._dismissedAt)).toHaveLength(2);
    const receipt = [...state.tables.expenses.values()].find((e) => e._receipt === "pending")!;
    const filename = receipt.receipt_storage_path!.replace("/", "__");
    expect(readFileSync(join(runtime.root, "Documents", "receipts", filename))).toEqual(readFileSync(join(fixtures, filename)));
    expect(existsSync(join(runtime.root, "Library", "Application Support", "ReceiptUploads.expo-imported-v1", filename))).toBe(true);
    await store.close();
    store = await openStore(userId);
    expect(store.getState().tables.expenses.size).toBe(12);
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(true);
  });

  it("is idempotent and shares concurrent calls", async () => {
    installFixture();
    store = await openStore(userId);
    const first = importLegacyData(store, userId);
    expect(importLegacyData(store, userId)).toBe(first);
    await first;
    const expense = [...store.getState().tables.expenses.values()][0]!;
    await store.commit([{ table: "expenses", row: { ...expense, description: "New edit after migration" } }]);
    expect((await importLegacyData(store, userId)).status).toBe("already-imported");
    expect(store.getState().tables.expenses.get(expense.id)?.description).toBe("New edit after migration");
  });

  it("includes an uncheckpointed WAL without opening the source database", async () => {
    installFixture();
    const writer = new DatabaseSync(sourcePath());
    writer.exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; UPDATE ZPROFILEENTITY SET ZDISPLAYNAME='WAL-only profile edit'");
    expect(existsSync(sourcePath() + "-wal")).toBe(true);
    store = await openStore(userId);
    try {
      expect((await importLegacyData(store, userId)).status).toBe("imported");
      expect(store.getState().tables.profiles.get(userId)?.display_name).toBe("WAL-only profile edit");
      expect(runtime.opens).not.toContain(sourcePath());
    } finally { writer.close(); }
  });

  it("retains all originals when persistence fails and retries after reopening", async () => {
    installFixture();
    store = await openStore(userId);
    runtime.failWrites = true;
    expect((await importLegacyData(store, userId)).status).toBe("failed");
    expect(existsSync(sourcePath())).toBe(true);
    runtime.failWrites = false;
    expect((await importLegacyData(store, userId)).status).toBe("failed");
    await store.close();
    store = await openStore(userId);
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(false);
    expect((await importLegacyData(store, userId)).status).toBe("imported");
  });

  it("retains the legacy store if session cleanup closes the destination before commit", async () => {
    installFixture();
    store = await openStore(userId);
    await store.close();
    expect((await importLegacyData(store, userId)).status).toBe("failed");
    expect(existsSync(sourcePath())).toBe(true);
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(false);
  });

  it("retries a failed archive without importing rows again", async () => {
    installFixture();
    store = await openStore(userId);
    runtime.failArchive = true;
    expect(await importLegacyData(store, userId)).toMatchObject({ status: "imported", archived: false });
    expect(existsSync(sourcePath())).toBe(true);
    runtime.failArchive = false;
    expect(await importLegacyData(store, userId)).toMatchObject({ status: "already-imported", archived: true });
  });

  it("does not import another account's data", async () => {
    installFixture();
    const other = "ffffffff-ffff-ffff-ffff-ffffffffffff";
    store = await openStore(other);
    expect((await importLegacyData(store, other)).status).toBe("account-mismatch");
    expect(store.getState().tables.trips.size).toBe(0);
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(false);
    expect(existsSync(sourcePath())).toBe(true);
  });

  it("does not consume the legacy store for a mismatched Store argument", async () => {
    installFixture();
    store = await openStore(userId);
    expect((await importLegacyData(store, "ffffffff-ffff-ffff-ffff-ffffffffffff")).status).toBe("account-mismatch");
    expect(existsSync(sourcePath())).toBe(true);
  });

  it("retains unknown or corrupted stores and never rejects startup", async () => {
    installFixture();
    const db = new DatabaseSync(sourcePath());
    db.exec("DROP TABLE ZPAYMENTENTITY");
    db.close();
    store = await openStore(userId);
    await expect(importLegacyData(store, userId)).resolves.toMatchObject({ status: "failed" });
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(false);
    expect(existsSync(sourcePath())).toBe(true);
    expect(warn).toHaveBeenCalled();
  });

  it("keeps both receipts when a different Expo receipt occupies the same path", async () => {
    installFixture();
    const filename = readdirSync(fixtures).find((name) => name.endsWith(".jpg"))!;
    const dir = join(runtime.root, "Documents", "receipts");
    mkdirSync(dir);
    writeFileSync(join(dir, filename), "A different pending receipt");
    store = await openStore(userId);
    expect((await importLegacyData(store, userId)).status).toBe("failed");
    expect(existsSync(sourcePath())).toBe(true);
    expect(readFileSync(join(dir, filename), "utf8")).toBe("A different pending receipt");
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(false);
  });

  it("does nothing on Android or a fresh iOS install", async () => {
    store = await openStore(userId);
    runtime.platform = "android";
    expect((await importLegacyData(store, userId)).status).toBe("unsupported");
    runtime.platform = "ios";
    expect((await importLegacyData(store, userId)).status).toBe("not-found");
    expect(store.getState().meta.has(IMPORT_MARKER)).toBe(false);
  });
});
