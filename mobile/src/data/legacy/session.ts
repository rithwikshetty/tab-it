import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

import { config } from "@/lib/config";

import { deleteLegacySession, readLegacySession } from "../../../modules/legacy-keychain";
import { legacyUUID } from "./convert";

export const LEGACY_KEYCHAIN_SERVICE = "supabase.gotrue.swift";

export interface LegacySession {
  refreshToken: string;
  legacyUserId: string;
}

export function legacySessionKey(supabaseUrl: string): string | null {
  try {
    const host = new URL(supabaseUrl).hostname.split(".")[0];
    return host ? `sb-${host}-auth-token` : null;
  } catch {
    return null;
  }
}

function sessionObject(value: string): Record<string, unknown> | null {
  try {
    const parsed: unknown = JSON.parse(value);
    if (!parsed || typeof parsed !== "object") return null;
    const root = parsed as Record<string, unknown>;
    return root.session && typeof root.session === "object" ? (root.session as Record<string, unknown>) : root;
  } catch {
    return null;
  }
}

export function legacyRefreshToken(value: string): string | null {
  const session = sessionObject(value);
  const token = session?.refreshToken ?? session?.refresh_token;
  return typeof token === "string" && token.trim().length ? token : null;
}

export function decodeLegacySession(value: string): LegacySession | null {
  const session = sessionObject(value);
  const refreshToken = legacyRefreshToken(value);
  const user = session?.user;
  const id = user && typeof user === "object" ? (user as Record<string, unknown>).id : null;
  if (!refreshToken || typeof id !== "string") return null;
  try {
    return { refreshToken, legacyUserId: legacyUUID(id) };
  } catch {
    return null;
  }
}

let restored: { key: string; session: LegacySession } | null = null;

export async function restoreLegacySession(): Promise<LegacySession | null> {
  restored = null;
  try {
    if (Platform.OS !== "ios") return null;
    const key = legacySessionKey(config.supabaseUrl);
    if (!key) return null;
    const value = await readLegacySession(LEGACY_KEYCHAIN_SERVICE, key);
    const session = value ? decodeLegacySession(value) : null;
    restored = session ? { key, session } : null;
    return session;
  } catch {
    console.warn("[legacy] Could not read the legacy session; its Keychain item was retained.");
    return null;
  }
}

export async function legacyImportUserId(): Promise<string | undefined> {
  if (Platform.OS !== "ios") return undefined;
  const key = legacySessionKey(config.supabaseUrl);
  if (!key) return undefined;
  const id = await SecureStore.getItemAsync(`legacy.swiftData.userId.${key}`);
  return id ?? (await restoreLegacySession())?.legacyUserId;
}

export async function clearLegacySession(): Promise<boolean> {
  try {
    if (Platform.OS !== "ios" || !restored) return false;
    const item = restored;
    await SecureStore.setItemAsync(`legacy.swiftData.userId.${item.key}`, item.session.legacyUserId);
    const deleted = await deleteLegacySession(LEGACY_KEYCHAIN_SERVICE, item.key);
    if (restored === item) restored = null;
    return deleted;
  } catch {
    console.warn("[legacy] Could not clear the legacy session.");
    return false;
  }
}

/** Deletes the Swift app's saved session so it can't sign anyone back in after they sign out. */
export async function forgetLegacySession(): Promise<void> {
  restored = null;
  if (Platform.OS !== "ios") return;
  const key = legacySessionKey(config.supabaseUrl);
  if (!key) return;
  try {
    await deleteLegacySession(LEGACY_KEYCHAIN_SERVICE, key);
  } catch {
    console.warn("[legacy] Could not clear the legacy session.");
  }
}
