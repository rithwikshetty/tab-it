import { beforeEach, expect, test, vi } from "vitest";

const keychain = vi.hoisted(() => ({ items: new Map<string, string>(), failOnSet: 0 }));

vi.mock("expo-secure-store", () => ({
  getItemAsync: async (key: string) => keychain.items.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => {
    if (keychain.failOnSet && --keychain.failOnSet === 0) throw new Error("killed");
    keychain.items.set(key, value);
  },
  deleteItemAsync: async (key: string) => void keychain.items.delete(key),
}));
vi.mock("expo-crypto", () => ({}));
vi.mock("react-native", () => ({ AppState: { addEventListener: vi.fn() } }));
vi.mock("./config", () => ({ config: { supabaseUrl: "", supabaseKey: "" } }));
vi.mock("@supabase/supabase-js", () => ({
  createClient: (_url: string, _key: string, options: { auth: { storage: unknown } }) => ({ auth: { storage: options.auth.storage } }),
}));

import type { SupportedStorage } from "@supabase/supabase-js";

import { supabase } from "./supabase";

const storage = (supabase.auth as unknown as { storage: SupportedStorage }).storage;
const KEY = "sb-test-auth-token";
const long = (seed: string) => seed.repeat(4000).slice(0, 4000);

beforeEach(() => {
  keychain.items.clear();
  keychain.failOnSet = 0;
});

test("a value longer than one chunk reads back whole", async () => {
  await storage.setItem(KEY, long("ab"));
  expect(await storage.getItem(KEY)).toBe(long("ab"));
});

test("a shorter value leaves none of the longer one behind", async () => {
  await storage.setItem(KEY, long("ab"));
  await storage.setItem(KEY, long("cd"));
  await storage.setItem(KEY, "short");
  expect(await storage.getItem(KEY)).toBe("short");
  expect([...keychain.items.keys()].sort()).toEqual([`${KEY}.a.0`, `${KEY}.at`]);
});

test("a write cut short leaves the stored value whole", async () => {
  await storage.setItem(KEY, long("ab"));
  keychain.failOnSet = 2;
  await expect(storage.setItem(KEY, long("cd"))).rejects.toThrow("killed");
  expect(await storage.getItem(KEY)).toBe(long("ab"));
  await storage.setItem(KEY, long("ef"));
  expect(await storage.getItem(KEY)).toBe(long("ef"));
});

test("a session saved by a build up to 2.0.0 is read, then moved to a slot", async () => {
  keychain.items.set(`${KEY}.n`, "2");
  keychain.items.set(`${KEY}.0`, "first-");
  keychain.items.set(`${KEY}.1`, "second");
  expect(await storage.getItem(KEY)).toBe("first-second");

  keychain.failOnSet = 2;
  await expect(storage.setItem(KEY, long("cd"))).rejects.toThrow("killed");
  expect(await storage.getItem(KEY)).toBe("first-second");

  await storage.setItem(KEY, "next");
  expect(await storage.getItem(KEY)).toBe("next");
  expect([...keychain.items.keys()].sort()).toEqual([`${KEY}.a.0`, `${KEY}.at`]);
});

test("removing clears every layout", async () => {
  keychain.items.set(`${KEY}.n`, "1");
  keychain.items.set(`${KEY}.0`, "old");
  await storage.setItem(KEY, long("ab"));
  keychain.items.set(`${KEY}.0`, "stray");
  await storage.removeItem(KEY);
  expect(await storage.getItem(KEY)).toBeNull();
  expect(keychain.items.size).toBe(0);
});
