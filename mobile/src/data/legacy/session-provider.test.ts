import type { Session } from "@supabase/supabase-js";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { SessionProvider } from "../session";

const mocks = vi.hoisted(() => ({
  effects: [] as (() => void | (() => void))[],
  useState: vi.fn(),
  useRef: vi.fn(),
  loadInitialSession: vi.fn(),
  importLegacyData: vi.fn(),
  openStore: vi.fn(),
  onAuthStateChange: vi.fn(),
  unsubscribe: vi.fn(),
  rpc: vi.fn(),
  createEngine: vi.fn(),
  start: vi.fn(),
  stop: vi.fn(),
  close: vi.fn(),
}));

vi.mock("react", async (original) => ({
  ...(await original<typeof import("react")>()),
  useState: mocks.useState,
  useRef: mocks.useRef,
  useEffect: (effect: () => void | (() => void)) => {
    mocks.effects.push(effect);
  },
  useMemo: (factory: () => unknown) => factory(),
}));
vi.mock("@/lib/supabase", () => ({ supabase: { auth: { onAuthStateChange: mocks.onAuthStateChange }, rpc: mocks.rpc } }));
vi.mock("../legacy", () => ({ importLegacyData: mocks.importLegacyData }));
vi.mock("./startup", () => ({ loadInitialSession: mocks.loadInitialSession }));
vi.mock("../store", () => ({ openStore: mocks.openStore, deleteStore: vi.fn() }));
vi.mock("../sync", () => ({
  SyncEngine: class {
    constructor(...args: unknown[]) {
      mocks.createEngine(...args);
    }
    start = mocks.start;
    stop = mocks.stop;
  },
}));

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((done, fail) => {
    resolve = done;
    reject = fail;
  });
  return { promise, resolve, reject };
}

const userId = "11111111-1111-1111-1111-111111111111";
const session = { user: { id: userId, email: "test@example.test", user_metadata: {} } } as Session;
const store = { userId, close: mocks.close };
const setSession = vi.fn();
const setOpened = vi.fn();
const legacyUser = { current: userId as string | undefined };

function render(current: Session | null | undefined = session, opened: unknown = null) {
  mocks.effects.length = 0;
  mocks.useState.mockReturnValueOnce([current, setSession]).mockReturnValueOnce([opened, setOpened]);
  return SessionProvider({ children: null as ReactNode });
}

beforeEach(() => {
  vi.resetAllMocks();
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
  legacyUser.current = userId;
  mocks.useRef.mockReturnValue(legacyUser);
  mocks.openStore.mockResolvedValue(store);
  mocks.importLegacyData.mockResolvedValue({ status: "imported" });
  mocks.loadInitialSession.mockResolvedValue({ session, legacyUserId: userId });
  mocks.onAuthStateChange.mockReturnValue({ data: { subscription: { unsubscribe: mocks.unsubscribe } } });
  mocks.rpc.mockResolvedValue({ error: null });
  mocks.close.mockResolvedValue(undefined);
});

afterEach(() => vi.restoreAllMocks());

describe("session provider startup effects", () => {
  it("keeps loading through initial auth events and refresh until the handoff finishes", async () => {
    const loading = deferred<{ session: Session | null; legacyUserId: string }>();
    mocks.loadInitialSession.mockReturnValue(loading.promise);
    const view = render(undefined);
    expect(view.props.value.status).toBe("loading");
    const cleanup = mocks.effects[0]!();
    const listener = mocks.onAuthStateChange.mock.calls[0]![0];
    listener("INITIAL_SESSION", null);
    listener("TOKEN_REFRESHED", session);
    expect(setSession).not.toHaveBeenCalled();
    loading.resolve({ session, legacyUserId: userId });
    await vi.waitFor(() => expect(setSession).toHaveBeenCalledWith(session));
    expect(legacyUser.current).toBe(userId);
    listener("INITIAL_SESSION", null);
    expect(setSession).toHaveBeenCalledTimes(1);
    listener("SIGNED_OUT", null);
    expect(setSession).toHaveBeenLastCalledWith(null);
    if (cleanup) cleanup();
    listener("SIGNED_IN", session);
    expect(setSession).toHaveBeenCalledTimes(2);
    expect(mocks.unsubscribe).toHaveBeenCalledOnce();
  });

  it("does not publish an auth result after unmount", async () => {
    const loading = deferred<{ session: Session; legacyUserId: string }>();
    mocks.loadInitialSession.mockReturnValue(loading.promise);
    render(undefined);
    const cleanup = mocks.effects[0]!();
    if (cleanup) cleanup();
    loading.resolve({ session, legacyUserId: userId });
    await loading.promise;
    expect(setSession).not.toHaveBeenCalled();
  });

  it("shows sign-in after a failed handoff even if a refresh notification arrived first", async () => {
    const loading = deferred<{ session: Session | null }>();
    mocks.loadInitialSession.mockReturnValue(loading.promise);
    render(undefined);
    const cleanup = mocks.effects[0]!();
    const listener = mocks.onAuthStateChange.mock.calls[0]![0];
    listener("TOKEN_REFRESHED", session);
    loading.resolve({ session: null });
    await vi.waitFor(() => expect(setSession).toHaveBeenCalledWith(null));
    if (cleanup) cleanup();
  });

  it("preserves a sign-out that arrives during startup", async () => {
    const loading = deferred<{ session: Session }>();
    mocks.loadInitialSession.mockReturnValue(loading.promise);
    render(undefined);
    const cleanup = mocks.effects[0]!();
    const listener = mocks.onAuthStateChange.mock.calls[0]![0];
    listener("SIGNED_OUT", null);
    loading.resolve({ session });
    await vi.waitFor(() => expect(setSession).toHaveBeenCalledWith(null));
    if (cleanup) cleanup();
  });

  it("awaits import before publishing the store, constructing sync, or claiming people", async () => {
    const importing = deferred<{ status: string }>();
    mocks.importLegacyData.mockReturnValue(importing.promise);
    render();
    const cleanup = mocks.effects[1]!();
    await vi.waitFor(() => expect(mocks.importLegacyData).toHaveBeenCalledWith(store, userId, { legacyUserId: userId }));
    expect(mocks.createEngine).not.toHaveBeenCalled();
    expect(setOpened).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
    importing.resolve({ status: "imported" });
    await vi.waitFor(() => expect(mocks.start).toHaveBeenCalledOnce());
    expect(setOpened).toHaveBeenCalledOnce();
    expect(mocks.createEngine).toHaveBeenCalledWith(store, expect.objectContaining({ id: userId }));
    expect(mocks.rpc).toHaveBeenCalledWith("claim_trip_people_for_current_email");
    if (cleanup) cleanup();
    await vi.waitFor(() => expect(mocks.close).toHaveBeenCalledOnce());
  });

  it("waits for an in-flight import before closing and never starts a cancelled engine", async () => {
    const importing = deferred<{ status: string }>();
    mocks.importLegacyData.mockReturnValue(importing.promise);
    render();
    const cleanup = mocks.effects[1]!();
    await vi.waitFor(() => expect(mocks.importLegacyData).toHaveBeenCalledOnce());
    if (cleanup) cleanup();
    expect(mocks.close).not.toHaveBeenCalled();
    importing.resolve({ status: "imported" });
    await vi.waitFor(() => expect(mocks.close).toHaveBeenCalledOnce());
    expect(mocks.createEngine).not.toHaveBeenCalled();
    expect(setOpened).not.toHaveBeenCalled();
  });

  it("closes a store that finishes opening after unmount without importing it", async () => {
    const opening = deferred<typeof store>();
    mocks.openStore.mockReturnValue(opening.promise);
    render();
    const cleanup = mocks.effects[1]!();
    if (cleanup) cleanup();
    opening.resolve(store);
    await vi.waitFor(() => expect(mocks.close).toHaveBeenCalledOnce());
    expect(mocks.importLegacyData).not.toHaveBeenCalled();
    expect(setOpened).not.toHaveBeenCalled();
  });

  it.each(["failed", "account-mismatch", "reject"])("logs an import %s and continues normal use", async (failure) => {
    if (failure === "reject") mocks.importLegacyData.mockRejectedValue(new Error("fictional-secret"));
    else mocks.importLegacyData.mockResolvedValue({ status: failure });
    render();
    const cleanup = mocks.effects[1]!();
    await vi.waitFor(() => expect(mocks.start).toHaveBeenCalledOnce());
    expect(setOpened).toHaveBeenCalledOnce();
    expect(console.warn).toHaveBeenCalledWith(expect.stringContaining("retry on the next launch"));
    expect(JSON.stringify(vi.mocked(console.warn).mock.calls)).not.toContain("fictional-secret");
    if (cleanup) cleanup();
  });

  it("can close after import while the claim request is still pending", async () => {
    const claim = deferred<{ error: null }>();
    mocks.rpc.mockReturnValue(claim.promise);
    render();
    const cleanup = mocks.effects[1]!();
    await vi.waitFor(() => expect(mocks.rpc).toHaveBeenCalledOnce());
    if (cleanup) cleanup();
    await vi.waitFor(() => expect(mocks.close).toHaveBeenCalledOnce());
    claim.resolve({ error: null });
    await claim.promise;
    expect(mocks.start).not.toHaveBeenCalled();
    expect(mocks.stop).toHaveBeenCalledOnce();
  });

  it("preserves the opened signedIn object across token refresh renders", () => {
    const opened = { user: { id: userId, email: null, displayName: "Test" }, store, sync: {} };
    const first = render(session, opened);
    const refreshed = render({ ...session, access_token: "rotated" }, opened);
    expect(first.props.value.signedIn).toBe(opened);
    expect(refreshed.props.value.signedIn).toBe(first.props.value.signedIn);
  });
});
