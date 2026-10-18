import { beforeEach, describe, expect, it, vi } from "vitest";

const native = vi.hoisted(() => ({
  os: "ios", getItemAsync: vi.fn(), deleteItemAsync: vi.fn(),
}));

vi.mock("react-native", () => ({ Platform: { get OS() { return native.os; } } }));
vi.mock("expo-secure-store", () => ({ getItemAsync: native.getItemAsync, deleteItemAsync: native.deleteItemAsync }));
vi.mock("@/lib/config", () => ({ config: { supabaseUrl: "http://127.0.0.1:54321" } }));

import { clearLegacySession, LEGACY_KEYCHAIN_SERVICE, legacyRefreshToken, legacySessionKey, restoreLegacySession } from "./session";

beforeEach(async () => {
  native.os = "ios";
  native.deleteItemAsync.mockResolvedValue(undefined);
  await clearLegacySession();
  vi.clearAllMocks();
  native.getItemAsync.mockResolvedValue(null);
});

describe("legacy native auth storage", () => {
  it("derives the exact project-scoped account without making a request", () => {
    expect(LEGACY_KEYCHAIN_SERVICE).toBe("supabase.gotrue.swift");
    expect(legacySessionKey("http://127.0.0.1:54321")).toBe("sb-127-auth-token");
    expect(legacySessionKey("https://fixture-project.example.test")).toBe("sb-fixture-project-auth-token");
    expect(legacySessionKey("")).toBeNull();
  });

  it("decodes JSONEncoder's camelCase session and older snake_case wrappers", () => {
    expect(legacyRefreshToken('{"refreshToken":"fictional-refresh-token","user":{"id":"fictional"}}')).toBe("fictional-refresh-token");
    expect(legacyRefreshToken('{"session":{"refresh_token":"older-fictional-token"}}')).toBe("older-fictional-token");
    expect(legacyRefreshToken('{"accessToken":"not-a-refresh-token"}')).toBeNull();
    expect(legacyRefreshToken('{"refreshToken":"   "}')).toBeNull();
    expect(legacyRefreshToken("not-json")).toBeNull();
  });

  it("returns the refresh token while leaving the item until the caller clears it", async () => {
    native.getItemAsync.mockResolvedValue('{"refreshToken":"fictional-token"}');
    expect(await restoreLegacySession()).toBe("fictional-token");
    expect(native.getItemAsync).toHaveBeenCalledWith("sb-127-auth-token", { keychainService: LEGACY_KEYCHAIN_SERVICE });
    expect(native.deleteItemAsync).not.toHaveBeenCalled();
    expect(await clearLegacySession()).toBe(true);
    expect(native.deleteItemAsync).toHaveBeenCalledWith("sb-127-auth-token", { keychainService: LEGACY_KEYCHAIN_SERVICE });
    expect(await clearLegacySession()).toBe(false);
  });

  it("handles the real SecureStore query mismatch without deleting the old item", async () => {
    native.getItemAsync.mockResolvedValue(null);
    expect(await restoreLegacySession()).toBeNull();
    expect(await clearLegacySession()).toBe(false);
    expect(native.deleteItemAsync).not.toHaveBeenCalled();
  });

  it("contains Keychain errors and never logs token contents", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    native.getItemAsync.mockRejectedValue(new Error("fictional-secret-must-not-be-logged"));
    await expect(restoreLegacySession()).resolves.toBeNull();
    expect(JSON.stringify(warning.mock.calls)).not.toContain("fictional-secret-must-not-be-logged");
    warning.mockRestore();
  });

  it("does not read iOS Keychain on other platforms", async () => {
    native.os = "android";
    expect(await restoreLegacySession()).toBeNull();
    expect(native.getItemAsync).not.toHaveBeenCalled();
  });
});
