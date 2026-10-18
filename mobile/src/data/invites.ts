import * as SecureStore from "expo-secure-store";

// An invite link (tab-it.app/join/<token>) can arrive before sign-in. The
// token waits here until a signed-in session can redeem it.

const KEY = "invite.pendingToken";

export function isInviteToken(token: string): boolean {
  return /^[0-9a-f]{32}$/.test(token);
}

export async function savePendingInvite(token: string) {
  if (isInviteToken(token)) await SecureStore.setItemAsync(KEY, token);
}

export async function takePendingInvite(): Promise<string | null> {
  const token = await SecureStore.getItemAsync(KEY);
  if (token) await SecureStore.deleteItemAsync(KEY);
  return token;
}
