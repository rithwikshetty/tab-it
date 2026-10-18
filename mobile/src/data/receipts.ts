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

function pendingFile(path: string): File {
  return new File(pendingDir(), path.replace("/", "__"));
}

/** The on-device copy of a receipt that hasn't finished uploading. */
export function localReceiptUri(path: string): string | null {
  const file = pendingFile(path);
  return file.exists ? file.uri : null;
}

/**
 * Turns a picked photo into a JPEG no larger than 2048px on its long edge and
 * under the bucket's size limit, and stores it as the pending upload for
 * `path`.
 */
export async function stageReceipt(source: { uri: string; width: number; height: number }, path: string): Promise<void> {
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
      const target = pendingFile(path);
      if (target.exists) target.delete();
      file.move(target);
      return;
    }
    file.delete();
    edge = Math.floor(edge * 0.75);
    if (edge < 480) throw new Error("That photo is too large to attach.");
  }
}

export function discardStagedReceipt(path: string) {
  const file = pendingFile(path);
  if (file.exists) file.delete();
}

/** Uploads receipts whose expenses have reached the server. */
export async function uploadPendingReceipts(store: Store): Promise<void> {
  for (const expense of store.getState().tables.expenses.values()) {
    if (expense._receipt !== "pending" || isDirty(expense) || expense.deleted_at) continue;
    const path = expense.receipt_storage_path;
    const file = path ? pendingFile(path) : null;
    let outcome: "done" | "failed" = "done";
    if (path && file?.exists) {
      try {
        const bytes = await file.bytes();
        await call(
          supabase.storage.from(BUCKET).upload(path, bytes, { contentType: "image/jpeg", upsert: true }) as never,
        );
        file.delete();
      } catch (error) {
        const e = toRemoteError(error);
        if (e.transient) throw e;
        console.warn(`[receipts] upload refused for ${path}: ${e.message}`);
        outcome = "failed";
      }
    }
    const current = store.getState().tables.expenses.get(expense.id);
    if (current) {
      await store.commit([{ table: "expenses", row: { ...current, _receipt: outcome === "done" ? null : "failed" } } as Op]);
    }
  }
}

const signed = new Map<string, { url: string; expires: number }>();

/** A URL the image view can load: the local pending copy, or a signed URL. */
export async function receiptSource(path: string): Promise<{ uri: string; cacheKey: string }> {
  const local = localReceiptUri(path);
  if (local) return { uri: local, cacheKey: `local:${path}` };
  const hit = signed.get(path);
  if (hit && hit.expires > Date.now()) return { uri: hit.url, cacheKey: path };
  const { signedUrl } = await call(supabase.storage.from(BUCKET).createSignedUrl(path, 3600) as never) as { signedUrl: string };
  signed.set(path, { url: signedUrl, expires: Date.now() + 50 * 60_000 });
  return { uri: signedUrl, cacheKey: path };
}
