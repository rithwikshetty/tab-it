import { Directory, File, Paths } from "expo-file-system";
import { ImageManipulator, SaveFormat } from "expo-image-manipulator";

import { supabase } from "@/lib/supabase";

import { call, toRemoteError } from "./remote";
import { isDirty, type Op } from "./schema";
import type { Store } from "./store";

// Receipt photos live in the private `receipts` bucket at
// `<trip_id>/<expense_id>.jpg`. Storage policies only let the expense's
// creator write that object, and only once the expense row exists on the
// server, so a new receipt waits on this phone (documents/receipts) until its
// expense has been pushed, then uploads.

const BUCKET = "receipts";
const MAX_EDGE = 2048;
const MAX_BYTES = 9_500_000;
const QUALITY = 0.92;

export function receiptPath(tripId: string, expenseId: string): string {
  return `${tripId}/${expenseId}.jpg`;
}

function pendingDir(): Directory {
  const dir = new Directory(Paths.document, "receipts");
  if (!dir.exists) dir.create({ intermediates: true });
  return dir;
}

/** The file name used for a pending photo; older (imported) photos have no version. */
function fileNameFor(path: string, version?: string | null): string {
  const base = path.replace("/", "__");
  return version ? base.replace(/\.jpg$/, `.${version}.jpg`) : base;
}

/** The on-device copy of a receipt that hasn't finished uploading. */
export function localReceiptUri(path: string, file?: string | null): string | null {
  const f = new File(pendingDir(), file ?? fileNameFor(path));
  return f.exists ? f.uri : null;
}

/**
 * Turns a picked photo into a JPEG no larger than 2048px on its long edge and
 * under the bucket's size limit, and stores it as a pending upload for
 * `path`. Each photo gets its own file name, so replacing a photo while an
 * older one uploads can't overwrite or lose the newer one. Returns that name.
 */
export async function stageReceipt(source: { uri: string; width: number; height: number }, path: string, version: string): Promise<string> {
  let edge = Math.min(MAX_EDGE, Math.max(source.width, source.height));
  for (;;) {
    const context = ImageManipulator.manipulate(source.uri);
    if (Math.max(source.width, source.height) > edge) {
      context.resize(source.width >= source.height ? { width: edge } : { height: edge });
    }
    const image = await context.renderAsync();
    const saved = await image.saveAsync({ compress: QUALITY, format: SaveFormat.JPEG });
    const file = new File(saved.uri);
    if ((file.size ?? 0) <= MAX_BYTES) {
      const name = fileNameFor(path, version);
      const target = new File(pendingDir(), name);
      if (target.exists) target.delete();
      await file.move(target);
      return name;
    }
    file.delete();
    edge = Math.floor(edge * 0.75);
    if (edge < 480) throw new Error("That photo is too large to attach.");
  }
}

/**
 * Deletes pending photos no expense refers to, left when the app quit during a
 * save. Runs when the store opens, before anything can stage a new one.
 */
export function pruneStagedReceipts(store: Store): void {
  const dir = new Directory(Paths.document, "receipts");
  if (!dir.exists) return;
  const wanted = new Set<string>();
  for (const e of store.getState().tables.expenses.values()) {
    if (e._receipt && e.receipt_storage_path) wanted.add(e._receiptFile ?? fileNameFor(e.receipt_storage_path));
  }
  for (const entry of dir.list()) {
    if (entry instanceof File && !wanted.has(entry.name)) entry.delete();
  }
}

export function discardStagedReceipt(path: string, file?: string | null) {
  const f = new File(pendingDir(), file ?? fileNameFor(path));
  if (f.exists) f.delete();
}

/** Uploads receipts whose expenses have reached the server. */
export async function uploadPendingReceipts(store: Store, alive: () => void): Promise<void> {
  for (const expense of store.getState().tables.expenses.values()) {
    if (expense._receipt !== "pending" || isDirty(expense) || expense.deleted_at || !expense.receipt_storage_path) continue;
    alive();
    const path = expense.receipt_storage_path;
    const name = expense._receiptFile ?? fileNameFor(path);
    const file = new File(pendingDir(), name);
    // A pending photo whose file is gone can't be sent; mark it failed so the
    // expense shows it needs a new photo instead of claiming one was saved.
    let outcome: "done" | "failed" = "failed";
    if (file.exists) {
      try {
        const bytes = await file.bytes();
        alive();
        await call(supabase.storage.from(BUCKET).upload(path, bytes, { contentType: "image/jpeg", upsert: true }) as never);
        file.delete();
        outcome = "done";
      } catch (error) {
        const e = toRemoteError(error);
        if (e.transient) throw e;
        console.warn(`[receipts] upload refused for ${path}: ${e.message}`);
      }
    }
    alive();
    // Only settle the photo that was uploaded; a newer one stays pending.
    const current = store.getState().tables.expenses.get(expense.id);
    if (current && current.receipt_storage_path === path && (current._receiptFile ?? fileNameFor(path)) === name) {
      await store.commit([
        {
          table: "expenses",
          row: { ...current, _receipt: outcome === "done" ? null : "failed", _receiptFile: outcome === "done" ? null : name },
        } as Op,
      ]);
    }
  }
}

const signed = new Map<string, { url: string; expires: number }>();

/**
 * A URL the image view can load: the local pending copy, or a signed URL.
 * `version` changes whenever the expense changes, so a replaced photo at the
 * same storage path isn't served from the image cache.
 */
export async function receiptSource(
  path: string,
  file: string | null | undefined,
  version: string,
): Promise<{ uri: string; cacheKey: string }> {
  const local = localReceiptUri(path, file);
  if (local) return { uri: local, cacheKey: `local:${local}` };
  const hit = signed.get(path);
  if (hit && hit.expires > Date.now()) return { uri: hit.url, cacheKey: `${path}#${version}` };
  const { signedUrl } = (await call(supabase.storage.from(BUCKET).createSignedUrl(path, 3600) as never)) as { signedUrl: string };
  signed.set(path, { url: signedUrl, expires: Date.now() + 50 * 60_000 });
  return { uri: signedUrl, cacheKey: `${path}#${version}` };
}
