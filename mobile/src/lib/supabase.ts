import { createClient, type SupportedStorage } from "@supabase/supabase-js";
import * as Crypto from "expo-crypto";
import * as SecureStore from "expo-secure-store";
import { AppState } from "react-native";

import { config } from "./config";
import type { Database } from "./database.types";

// Hermes has no WebCrypto. Auth hashes the PKCE challenge with
// crypto.subtle.digest and sends a plain challenge without it, so the native
// digest stands in for it.
const webCrypto = ((globalThis as { crypto?: { getRandomValues?: unknown; subtle?: unknown } }).crypto ??= {});
webCrypto.getRandomValues ??= Crypto.getRandomValues;
webCrypto.subtle ??= {
  digest: (algorithm: string, data: BufferSource) => Crypto.digest(algorithm as Crypto.CryptoDigestAlgorithm, data),
};

// The session (access + refresh token) lives in the iOS Keychain / Android
// Keystore. SecureStore values are kept small, so a long value is split into
// numbered chunks in one of two slots, and `<key>.at` holds the slot in use
// and its chunk count. A write fills the other slot and moves the pointer
// last, so a write that is cut short leaves the stored value whole.
// A session saved by a build up to 2.0.0 has no pointer: its count is under
// `<key>.n` and its chunks under `<key>.<i>`.
const CHUNK = 1800;

async function readChunks(prefix: string, count: number): Promise<string | null> {
  const parts: string[] = [];
  for (let i = 0; i < count; i++) {
    const part = await SecureStore.getItemAsync(`${prefix}.${i}`);
    if (part === null) return null;
    parts.push(part);
  }
  return parts.join("");
}

/** Deletes chunks from `from` up to the first one that is missing. */
async function deleteChunks(prefix: string, from: number): Promise<void> {
  for (let i = from; (await SecureStore.getItemAsync(`${prefix}.${i}`)) !== null; i++) {
    await SecureStore.deleteItemAsync(`${prefix}.${i}`);
  }
}

async function slotInUse(key: string): Promise<{ slot: string; count: number } | null> {
  const at = await SecureStore.getItemAsync(`${key}.at`);
  if (at === null) return null;
  return { slot: at.slice(0, 1), count: Number(at.slice(2)) };
}

const secureStorage: SupportedStorage = {
  async getItem(key) {
    const at = await slotInUse(key);
    if (at) return readChunks(`${key}.${at.slot}`, at.count);
    const count = await SecureStore.getItemAsync(`${key}.n`);
    return count === null ? null : readChunks(key, Number(count));
  },
  async setItem(key, value) {
    const at = await slotInUse(key);
    const slot = at?.slot === "a" ? "b" : "a";
    const count = Math.ceil(value.length / CHUNK);
    for (let i = 0; i < count; i++) {
      await SecureStore.setItemAsync(`${key}.${slot}.${i}`, value.slice(i * CHUNK, (i + 1) * CHUNK));
    }
    await deleteChunks(`${key}.${slot}`, count);
    await SecureStore.setItemAsync(`${key}.at`, `${slot}:${count}`);
    if (at) {
      await deleteChunks(`${key}.${at.slot}`, 0);
    } else {
      await SecureStore.deleteItemAsync(`${key}.n`);
      await deleteChunks(key, 0);
    }
  },
  async removeItem(key) {
    await SecureStore.deleteItemAsync(`${key}.at`);
    await SecureStore.deleteItemAsync(`${key}.n`);
    for (const prefix of [`${key}.a`, `${key}.b`, key]) await deleteChunks(prefix, 0);
  },
};

export const supabase = createClient<Database>(config.supabaseUrl || "http://127.0.0.1:54321", config.supabaseKey || "unconfigured", {
  auth: {
    storage: secureStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
    flowType: "pkce",
  },
});

// Token refresh only runs while the app is in the foreground.
AppState.addEventListener("change", (state) => {
  if (state === "active") supabase.auth.startAutoRefresh();
  else supabase.auth.stopAutoRefresh();
});
