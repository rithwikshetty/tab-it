import { beforeEach, expect, it, vi } from "vitest";

import { deleteLegacySession, readLegacySession } from "../../../modules/legacy-keychain";

const native = vi.hoisted(() => ({ os: "ios", requireOptionalNativeModule: vi.fn(), read: vi.fn(), remove: vi.fn() }));
vi.mock("react-native", () => ({
  Platform: {
    get OS() {
      return native.os;
    },
  },
}));
vi.mock("expo", () => ({ requireOptionalNativeModule: native.requireOptionalNativeModule }));

beforeEach(() => {
  vi.resetAllMocks();
  native.os = "ios";
  native.requireOptionalNativeModule.mockReturnValue({ readLegacySession: native.read, deleteLegacySession: native.remove });
});

it("passes exact service and string account arguments to the iOS module", async () => {
  native.read.mockResolvedValue("raw-json");
  native.remove.mockResolvedValue(true);
  expect(await readLegacySession("supabase.gotrue.swift", "sb-fixture-auth-token")).toBe("raw-json");
  expect(await deleteLegacySession("supabase.gotrue.swift", "sb-fixture-auth-token")).toBe(true);
  expect(native.requireOptionalNativeModule).toHaveBeenCalledWith("LegacyKeychain");
  expect(native.read).toHaveBeenCalledWith("supabase.gotrue.swift", "sb-fixture-auth-token");
  expect(native.remove).toHaveBeenCalledWith("supabase.gotrue.swift", "sb-fixture-auth-token");
});

it("no-ops on Android without looking up an iOS module", async () => {
  native.os = "android";
  expect(await readLegacySession("service", "account")).toBeNull();
  expect(await deleteLegacySession("service", "account")).toBe(false);
  expect(native.requireOptionalNativeModule).not.toHaveBeenCalled();
});

it("no-ops when the native module is not included in the binary", async () => {
  native.requireOptionalNativeModule.mockReturnValue(null);
  expect(await readLegacySession("service", "account")).toBeNull();
  expect(await deleteLegacySession("service", "account")).toBe(false);
});
