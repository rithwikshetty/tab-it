import type { Session, SupabaseClient } from "@supabase/supabase-js";

import { clearLegacySession, legacyImportUserId, restoreLegacySession } from "./session";

type Auth = Pick<SupabaseClient["auth"], "getSession" | "refreshSession">;

interface SessionStartup {
  session: Session | null;
  legacyUserId?: string;
}

const inFlight = new WeakMap<Auth, Promise<SessionStartup>>();

export async function withTimeout<T>(work: Promise<T>, milliseconds: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error("Session startup timed out")), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function loadSession(auth: Auth): Promise<SessionStartup> {
  let legacyUserId: string | undefined;
  try {
    const existing = await withTimeout(auth.getSession(), 10_000);
    if (existing.error) throw existing.error;
    if (existing.data.session) {
      try {
        legacyUserId = await withTimeout(legacyImportUserId(), 3_000);
      } catch {
        console.warn("[legacy] Could not read the legacy import account.");
      }
      return { session: existing.data.session, legacyUserId };
    }
    const legacy = await withTimeout(restoreLegacySession(), 3_000);
    if (!legacy) return { session: null };
    legacyUserId = legacy.legacyUserId;
    const refreshed = await withTimeout(auth.refreshSession({ refresh_token: legacy.refreshToken }), 15_000);
    if (refreshed.error || !refreshed.data.session) throw new Error("Legacy session refresh failed");
    if (refreshed.data.session.user.id.toLowerCase() !== legacyUserId) throw new Error("Legacy session account mismatch");
    try {
      await withTimeout(clearLegacySession(), 3_000);
    } catch {
      console.warn("[legacy] Could not finish clearing the legacy session.");
    }
    return { session: refreshed.data.session, legacyUserId };
  } catch {
    console.warn("[session] Could not restore the saved session; sign in to continue.");
    return { session: null, legacyUserId };
  }
}

export function loadInitialSession(auth: Auth): Promise<SessionStartup> {
  const running = inFlight.get(auth);
  if (running) return running;
  const promise = loadSession(auth).finally(() => inFlight.delete(auth));
  inFlight.set(auth, promise);
  return promise;
}
