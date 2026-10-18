import type { Session } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { loadInitialSession, withTimeout } from "./startup";

const legacy = vi.hoisted(() => ({ restoreLegacySession: vi.fn(), clearLegacySession: vi.fn(), legacyImportUserId: vi.fn() }));
vi.mock("./session", () => legacy);

const userId = "11111111-1111-1111-1111-111111111111";
const session = { user: { id: userId }, access_token: "fictional-access", refresh_token: "rotated-token" } as Session;
const restored = { refreshToken: "fictional-refresh", legacyUserId: userId };
const never = () => new Promise<never>(() => undefined);
const authClient = () => ({
  getSession: vi.fn().mockResolvedValue({ data: { session: null }, error: null }),
  refreshSession: vi.fn().mockResolvedValue({ data: { session, user: session.user }, error: null }),
});

beforeEach(() => {
  vi.useFakeTimers();
  vi.resetAllMocks();
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
  legacy.restoreLegacySession.mockResolvedValue(restored);
  legacy.clearLegacySession.mockResolvedValue(true);
  legacy.legacyImportUserId.mockResolvedValue(userId);
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("initial session handoff", () => {
  it("uses a saved JS session without refreshing and restores import account evidence", async () => {
    const auth = authClient();
    auth.getSession.mockResolvedValue({ data: { session }, error: null });
    expect(await loadInitialSession(auth)).toEqual({ session, legacyUserId: userId });
    expect(auth.refreshSession).not.toHaveBeenCalled();
    expect(legacy.restoreLegacySession).not.toHaveBeenCalled();
    expect(legacy.clearLegacySession).not.toHaveBeenCalled();
  });

  it("clears only after refreshSession has completed its persistence work", async () => {
    const auth = authClient();
    let finish!: (value: Awaited<ReturnType<typeof auth.refreshSession>>) => void;
    auth.refreshSession.mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    const loading = loadInitialSession(auth);
    await vi.advanceTimersByTimeAsync(0);
    expect(auth.refreshSession).toHaveBeenCalledWith({ refresh_token: restored.refreshToken });
    expect(legacy.clearLegacySession).not.toHaveBeenCalled();
    finish({ data: { session, user: session.user }, error: null });
    expect(await loading).toEqual({ session, legacyUserId: userId });
    expect(legacy.clearLegacySession).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });

  it("shares an in-flight refresh across overlapping provider effects", async () => {
    const auth = authClient();
    const first = loadInitialSession(auth);
    expect(loadInitialSession(auth)).toBe(first);
    await first;
    expect(auth.refreshSession).toHaveBeenCalledOnce();
    expect(legacy.clearLegacySession).toHaveBeenCalledOnce();
  });

  it("shows sign-in when no legacy session is present", async () => {
    const auth = authClient();
    legacy.restoreLegacySession.mockResolvedValue(null);
    expect(await loadInitialSession(auth)).toEqual({ session: null });
    expect(auth.refreshSession).not.toHaveBeenCalled();
    expect(legacy.clearLegacySession).not.toHaveBeenCalled();
  });

  it.each(["error", "empty", "reject", "mismatch"])("retains the native token after a refresh %s", async (failure) => {
    const auth = authClient();
    if (failure === "reject") auth.refreshSession.mockRejectedValue(new Error("fictional-secret"));
    else
      auth.refreshSession.mockResolvedValue({
        data: { session: failure === "mismatch" ? { ...session, user: { id: "different-user" } } : null },
        error: failure === "error" ? new Error("fictional-secret") : null,
      });
    expect(await loadInitialSession(auth)).toEqual({ session: null, legacyUserId: userId });
    expect(legacy.clearLegacySession).not.toHaveBeenCalled();
    expect(JSON.stringify(vi.mocked(console.warn).mock.calls)).not.toContain("fictional-secret");
  });

  it.each(["get", "read", "refresh"])("bounds a stalled %s operation and preserves the old token", async (stage) => {
    const auth = authClient();
    if (stage === "get") auth.getSession.mockImplementation(never);
    if (stage === "read") legacy.restoreLegacySession.mockImplementation(never);
    if (stage === "refresh") auth.refreshSession.mockImplementation(never);
    const loading = loadInitialSession(auth);
    await vi.advanceTimersByTimeAsync(35_000);
    expect((await loading).session).toBeNull();
    expect(legacy.clearLegacySession).not.toHaveBeenCalled();
  });

  it.each(["reject", "stall"])("still signs in if clearing the legacy item fails with %s", async (failure) => {
    const auth = authClient();
    if (failure === "reject") legacy.clearLegacySession.mockRejectedValue(new Error("fictional-secret"));
    else legacy.clearLegacySession.mockImplementation(never);
    const loading = loadInitialSession(auth);
    await vi.advanceTimersByTimeAsync(3_000);
    expect((await loading).session).toBe(session);
  });

  it("does not block a saved JS session on legacy account storage", async () => {
    const auth = authClient();
    auth.getSession.mockResolvedValue({ data: { session }, error: null });
    legacy.legacyImportUserId.mockImplementation(never);
    const loading = loadInitialSession(auth);
    await vi.advanceTimersByTimeAsync(3_000);
    expect((await loading).session).toBe(session);
  });

  it("cleans up timeout timers when an operation rejects", async () => {
    await expect(withTimeout(Promise.reject(new Error("failed")), 100)).rejects.toThrow("failed");
    expect(vi.getTimerCount()).toBe(0);
  });
});
