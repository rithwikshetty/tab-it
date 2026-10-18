import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  clearLegacySession,
  decodeLegacySession,
  LEGACY_KEYCHAIN_SERVICE,
  legacyImportUserId,
  legacyRefreshToken,
  legacySessionKey,
  restoreLegacySession,
} from "./session";

const native = vi.hoisted(() => ({
  os: "ios",
  readLegacySession: vi.fn(),
  deleteLegacySession: vi.fn(),
  getItemAsync: vi.fn(),
  setItemAsync: vi.fn(),
}));

vi.mock("react-native", () => ({
  Platform: {
    get OS() {
      return native.os;
    },
  },
}));
vi.mock("../../../modules/legacy-keychain", () => ({
  readLegacySession: native.readLegacySession,
  deleteLegacySession: native.deleteLegacySession,
}));
vi.mock("expo-secure-store", () => ({ getItemAsync: native.getItemAsync, setItemAsync: native.setItemAsync }));
vi.mock("@/lib/config", () => ({ config: { supabaseUrl: "http://127.0.0.1:54321" } }));

const userId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const saved = JSON.stringify({ refreshToken: "fictional-token", user: { id: userId } });

beforeEach(async () => {
  native.os = "ios";
  native.readLegacySession.mockResolvedValue(null);
  await restoreLegacySession();
  vi.resetAllMocks();
  native.readLegacySession.mockResolvedValue(null);
  native.deleteLegacySession.mockResolvedValue(true);
  native.getItemAsync.mockResolvedValue(null);
  native.setItemAsync.mockResolvedValue(undefined);
});

describe("legacy native auth storage", () => {
  it("derives the exact project-scoped string account without a request", () => {
    expect(LEGACY_KEYCHAIN_SERVICE).toBe("supabase.gotrue.swift");
    expect(legacySessionKey("http://127.0.0.1:54321")).toBe("sb-127-auth-token");
    expect(legacySessionKey("https://fixture-project.example.test/path")).toBe("sb-fixture-project-auth-token");
    expect(legacySessionKey("")).toBeNull();
    expect(legacySessionKey("not a URL")).toBeNull();
  });

  it("decodes camelCase and wrapped snake_case sessions with their original account", () => {
    expect(decodeLegacySession(saved)).toEqual({ refreshToken: "fictional-token", legacyUserId: userId });
    expect(decodeLegacySession(JSON.stringify({ session: { refresh_token: "older-token", user: { id: userId.toUpperCase() } } }))).toEqual({
      refreshToken: "older-token",
      legacyUserId: userId,
    });
    expect(legacyRefreshToken('{"refreshToken":"fictional-token"}')).toBe("fictional-token");
    for (const value of [
      "null",
      "[]",
      "not-json",
      '{"refreshToken":"   "}',
      '{"refreshToken":4}',
      '{"refreshToken":"token","user":{"id":"invalid"}}',
      '{"refreshToken":"token"}',
    ]) {
      expect(decodeLegacySession(value)).toBeNull();
    }
  });

  it("reads through the native query and retains the item until explicitly cleared", async () => {
    native.readLegacySession.mockResolvedValue(saved);
    expect(await restoreLegacySession()).toEqual({ refreshToken: "fictional-token", legacyUserId: userId });
    expect(native.readLegacySession).toHaveBeenCalledWith(LEGACY_KEYCHAIN_SERVICE, "sb-127-auth-token");
    expect(native.deleteLegacySession).not.toHaveBeenCalled();
    expect(await clearLegacySession()).toBe(true);
    expect(native.setItemAsync).toHaveBeenCalledWith("legacy.swiftData.userId.sb-127-auth-token", userId);
    expect(native.setItemAsync.mock.invocationCallOrder[0]).toBeLessThan(native.deleteLegacySession.mock.invocationCallOrder[0]!);
    expect(native.deleteLegacySession).toHaveBeenCalledWith(LEGACY_KEYCHAIN_SERVICE, "sb-127-auth-token");
    expect(await clearLegacySession()).toBe(false);
  });

  it("keeps account evidence for a retry after the native token was deleted", async () => {
    native.getItemAsync.mockResolvedValue(userId);
    expect(await legacyImportUserId()).toBe(userId);
    expect(native.readLegacySession).not.toHaveBeenCalled();
  });

  it("recovers account evidence from a retained native item", async () => {
    native.readLegacySession.mockResolvedValue(saved);
    expect(await legacyImportUserId()).toBe(userId);
  });

  it("preserves the token if saving the import account fails", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    native.readLegacySession.mockResolvedValue(saved);
    await restoreLegacySession();
    native.setItemAsync.mockRejectedValue(new Error("fictional-secret"));
    expect(await clearLegacySession()).toBe(false);
    expect(native.deleteLegacySession).not.toHaveBeenCalled();
    native.setItemAsync.mockResolvedValue(undefined);
    expect(await clearLegacySession()).toBe(true);
    expect(JSON.stringify(warning.mock.calls)).not.toContain("fictional-secret");
    warning.mockRestore();
  });

  it("retains a failed delete for retry and contains Keychain errors without logging secrets", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    native.readLegacySession.mockResolvedValue(saved);
    await restoreLegacySession();
    native.deleteLegacySession.mockRejectedValue(new Error("fictional-secret"));
    expect(await clearLegacySession()).toBe(false);
    native.deleteLegacySession.mockResolvedValue(true);
    expect(await clearLegacySession()).toBe(true);
    native.readLegacySession.mockRejectedValue(new Error("fictional-secret"));
    await expect(restoreLegacySession()).resolves.toBeNull();
    expect(JSON.stringify(warning.mock.calls)).not.toContain("fictional-secret");
    warning.mockRestore();
  });

  it("never deletes missing or malformed sessions", async () => {
    expect(await restoreLegacySession()).toBeNull();
    native.readLegacySession.mockResolvedValue('{"refreshToken":"token"}');
    expect(await restoreLegacySession()).toBeNull();
    expect(await clearLegacySession()).toBe(false);
    expect(native.deleteLegacySession).not.toHaveBeenCalled();
  });

  it("does no Keychain work on Android", async () => {
    native.os = "android";
    expect(await restoreLegacySession()).toBeNull();
    expect(await clearLegacySession()).toBe(false);
    expect(await legacyImportUserId()).toBeUndefined();
    expect(native.readLegacySession).not.toHaveBeenCalled();
    expect(native.getItemAsync).not.toHaveBeenCalled();
    expect(native.deleteLegacySession).not.toHaveBeenCalled();
  });
});
