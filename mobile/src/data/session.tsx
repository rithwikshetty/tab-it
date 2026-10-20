import type { Session, User } from "@supabase/supabase-js";
import { createContext, use, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";

import { supabase } from "@/lib/supabase";

import { importLegacyData } from "./legacy";
import { pruneStagedReceipts } from "./receipts";
import { loadInitialSession } from "./legacy/startup";
import type { State } from "./schema";
import { deleteStore, openStore, type Store } from "./store";
import { SyncEngine, type SyncStatus } from "./sync";

// Session lifecycle: Supabase's persisted session decides who is signed in;
// a signed-in user gets their own local database and sync engine. Signing out
// closes both and deletes that user's local data from the phone.

export interface CurrentUser {
  id: string;
  email: string | null;
  displayName: string;
}

export interface SignedIn {
  user: CurrentUser;
  store: Store;
  sync: SyncEngine;
}

interface SessionValue {
  status: "loading" | "signedOut" | "signedIn";
  user: CurrentUser | null;
  store: Store | null;
  sync: SyncEngine | null;
  /** Stable for the whole session, so effects can depend on it. */
  signedIn: SignedIn | null;
}

const LOADING: SessionValue = { status: "loading", user: null, store: null, sync: null, signedIn: null };
const SessionContext = createContext<SessionValue>(LOADING);

function currentUserFrom(user: User): CurrentUser {
  const meta = user.user_metadata ?? {};
  const email = user.email ? user.email.trim().toLowerCase() : null;
  const name = [meta.display_name, meta.given_name, meta.full_name, meta.name]
    .map((v) => (typeof v === "string" ? v.trim() : ""))
    .find((v) => v.length > 0);
  return { id: user.id, email, displayName: (name || email?.split("@")[0] || "You").slice(0, 60) };
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [opened, setOpened] = useState<SignedIn | null>(null);
  const legacyUserId = useRef<string | undefined>(undefined);

  useEffect(() => {
    let active = true;
    let loading = true;
    let pending: Session | null | undefined;
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      if (!active || event === "INITIAL_SESSION") return;
      if (loading) {
        if (event !== "TOKEN_REFRESHED") pending = next;
      } else setSession(next);
    });
    void loadInitialSession(supabase.auth).then((initial) => {
      if (!active) return;
      legacyUserId.current = initial.legacyUserId;
      loading = false;
      setSession(pending === undefined ? initial.session : pending);
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, []);

  const userId = session?.user.id ?? null;

  useEffect(() => {
    if (!userId || !session) {
      setOpened(null);
      return;
    }
    let cancelled = false;
    let engine: SyncEngine | null = null;
    let store: Store | null = null;
    const user = currentUserFrom(session.user);
    const opening = (async () => {
      store = await openStore(userId);
      if (cancelled) return;
      try {
        const imported = await importLegacyData(store, userId, { legacyUserId: legacyUserId.current });
        if (imported.status === "failed" || imported.status === "account-mismatch") {
          console.warn("[legacy] Import was deferred; it will retry on the next launch.");
        }
      } catch {
        console.warn("[legacy] Import did not complete; it will retry on the next launch.");
      }
      if (cancelled) return;
      try {
        pruneStagedReceipts(store);
      } catch {
        console.warn("[receipts] Could not tidy unused photos.");
      }
      engine = new SyncEngine(store, user);
      setOpened({ store, sync: engine, user });
      engine.start();
    })().catch(() => {
      console.warn("[session] Could not open the local store.");
    });
    return () => {
      cancelled = true;
      engine?.stop();
      void opening
        .then(() => store?.close())
        .catch(() => {
          console.warn("[session] Could not close the local store.");
        });
    };
    // The session object changes on every token refresh; only the user matters.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  const signedOut = session === null;
  const sessionUserId = session?.user.id;
  const value = useMemo<SessionValue>(() => {
    if (signedOut) return { ...LOADING, status: "signedOut" };
    if (!opened || opened.user.id !== sessionUserId) return LOADING;
    return { status: "signedIn", user: opened.user, store: opened.store, sync: opened.sync, signedIn: opened };
  }, [signedOut, sessionUserId, opened]);

  return <SessionContext value={value}>{children}</SessionContext>;
}

export function useSession(): SessionValue {
  return use(SessionContext);
}

/** For screens inside the signed-in area, where a store always exists. */
export function useSignedIn(): SignedIn {
  const { signedIn } = use(SessionContext);
  if (!signedIn) throw new Error("useSignedIn used outside the signed-in area");
  return signedIn;
}

/** The whole local state; re-renders on every commit. */
export function useAppState(): State {
  const { store } = useSignedIn();
  return useSyncExternalStore(store.subscribe, store.getState);
}

export function useSyncStatus(): SyncStatus {
  const { sync } = useSignedIn();
  return useSyncExternalStore(sync.subscribe, sync.getStatus);
}

/** Deletes everything this user had on the phone. */
export async function clearLocalData(userId: string) {
  await deleteStore(userId);
}
