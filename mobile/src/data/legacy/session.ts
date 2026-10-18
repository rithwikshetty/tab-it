import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

import { config } from "@/lib/config";

export const LEGACY_KEYCHAIN_SERVICE = "supabase.gotrue.swift";

export function legacySessionKey(supabaseUrl: string): string | null {
  try {
    const host = new URL(supabaseUrl).hostname.split(".")[0];
    return host ? `sb-${host}-auth-token` : null;
  } catch { return null; }
}

export function legacyRefreshToken(value: string): string | null {
  try {
    const parsed: unknown = JSON.parse(value);
    if (!parsed || typeof parsed !== "object") return null;
    const root = parsed as Record<string, unknown>;
    const session = root.session && typeof root.session === "object" ? root.session as Record<string, unknown> : root;
    const token = session.refreshToken ?? session.refresh_token;
    return typeof token === "string" && token.trim().length ? token : null;
  } catch { return null; }
}

let restoredKey: string | null = null;

export async function restoreLegacySession(): Promise<string | null> {
  try {
    if (Platform.OS !== "ios") return null;
    const key = legacySessionKey(config.supabaseUrl);
    if (!key) return null;
    const value = await SecureStore.getItemAsync(key, { keychainService: LEGACY_KEYCHAIN_SERVICE });
    const token = value ? legacyRefreshToken(value) : null;
    if (token) restoredKey = key;
    return token;
  } catch {
    console.warn("[legacy] Could not read the legacy session; its Keychain item was retained.");
    return null;
  }
}

export async function clearLegacySession(): Promise<boolean> {
  try {
    if (Platform.OS !== "ios" || !restoredKey) return false;
    await SecureStore.deleteItemAsync(restoredKey, { keychainService: LEGACY_KEYCHAIN_SERVICE });
    restoredKey = null;
    return true;
  } catch {
    console.warn("[legacy] Could not clear the legacy session.");
    return false;
  }
}
