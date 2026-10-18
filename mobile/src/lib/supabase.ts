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
// Keystore. SecureStore values are kept small, so long values are split
// across numbered chunks with a count stored under the base key.
const CHUNK = 1800;

const secureStorage: SupportedStorage = {
  async getItem(key) {
    const count = await SecureStore.getItemAsync(`${key}.n`);
    if (count === null) return null;
    const parts: string[] = [];
    for (let i = 0; i < Number(count); i++) {
      const part = await SecureStore.getItemAsync(`${key}.${i}`);
      if (part === null) return null;
      parts.push(part);
    }
    return parts.join("");
  },
  async setItem(key, value) {
    const previous = Number((await SecureStore.getItemAsync(`${key}.n`)) ?? 0);
    const count = Math.ceil(value.length / CHUNK);
    for (let i = 0; i < count; i++) {
      await SecureStore.setItemAsync(`${key}.${i}`, value.slice(i * CHUNK, (i + 1) * CHUNK));
    }
    await SecureStore.setItemAsync(`${key}.n`, String(count));
    for (let i = count; i < previous; i++) await SecureStore.deleteItemAsync(`${key}.${i}`);
  },
  async removeItem(key) {
    const count = Number((await SecureStore.getItemAsync(`${key}.n`)) ?? 0);
    await SecureStore.deleteItemAsync(`${key}.n`);
    for (let i = 0; i < count; i++) await SecureStore.deleteItemAsync(`${key}.${i}`);
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
