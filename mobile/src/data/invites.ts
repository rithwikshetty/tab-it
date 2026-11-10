import * as SecureStore from "expo-secure-store";

// An invite link (tab-it.app/join/<token>) can arrive before sign-in. The
// token waits here until a signed-in session can redeem it.

const KEY = "invite.pendingToken";

export function isInviteToken(token: string): boolean {
  return /^[0-9a-f]{32}$/.test(token);
}

const listeners = new Set<() => void>();

/** Calls `listener` whenever an invite is saved, so a signed-in session can redeem it at once. */
export function onPendingInvite(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export async function savePendingInvite(token: string) {
  if (!isInviteToken(token)) return;
  await SecureStore.setItemAsync(KEY, token);
  for (const listener of listeners) listener();
}

export async function takePendingInvite(): Promise<string | null> {
  const token = await SecureStore.getItemAsync(KEY);
  if (token) await SecureStore.deleteItemAsync(KEY);
  return token;
}
