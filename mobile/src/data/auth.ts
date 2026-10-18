import * as AppleAuthentication from "expo-apple-authentication";
import * as Crypto from "expo-crypto";
import { Directory, Paths } from "expo-file-system";
import * as Linking from "expo-linking";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";

import { AUTH_CALLBACK_URL, config } from "@/lib/config";
import { supabase } from "@/lib/supabase";

import { unregisterPushDevice } from "./push";
import type { Store } from "./store";
import { deleteStore } from "./store";
import type { SyncEngine } from "./sync";

// Sign-in methods: Sign in with Apple (iOS), Google through the system browser,
// and an emailed one-time code behind a Cloudflare Turnstile check. Local
// development against the Docker stack can also sign in with a password.

export const EMAIL_CODE_LENGTH = Number(process.env.EXPO_PUBLIC_EMAIL_CODE_LENGTH ?? 8);

export class AuthError extends Error {}

export function normalizeName(name: string | null | undefined): string | null {
  const trimmed = name?.trim() ?? "";
  return trimmed ? trimmed.slice(0, 60) : null;
}

export function normalizeEmailInput(email: string): string | null {
  const e = email.trim().toLowerCase();
  const [local, domain, ...rest] = e.split("@");
  if (rest.length || !local || !domain || !domain.includes(".") || e.includes(" ")) return null;
  return e;
}

function nameMetadata(name: string) {
  return { display_name: name, full_name: name, name };
}

function requireConfig() {
  if (!config.isConfigured) throw new AuthError("This build has no backend configured.");
}

function isCancel(error: unknown) {
  const code = (error as { code?: string })?.code;
  return code === "ERR_REQUEST_CANCELED" || code === "ERR_CANCELED";
}

/** Returns false when the user cancelled. */
export async function signInWithApple(): Promise<boolean> {
  requireConfig();
  const rawNonce = `${Crypto.randomUUID()}${Crypto.randomUUID()}`;
  const hashed = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, rawNonce);
  let credential: AppleAuthentication.AppleAuthenticationCredential;
  try {
    credential = await AppleAuthentication.signInAsync({
      requestedScopes: [AppleAuthentication.AppleAuthenticationScope.FULL_NAME, AppleAuthentication.AppleAuthenticationScope.EMAIL],
      nonce: hashed,
    });
  } catch (error) {
    if (isCancel(error)) return false;
    throw error;
  }
  if (!credential.identityToken) throw new AuthError("Apple didn't return an identity token.");
  const { error } = await supabase.auth.signInWithIdToken({
    provider: "apple",
    token: credential.identityToken,
    nonce: rawNonce,
  });
  if (error) throw new AuthError(error.message);
  // Apple shares the name only on the first authorisation; keep it.
  const name = normalizeName(
    [credential.fullName?.givenName, credential.fullName?.middleName, credential.fullName?.familyName].filter(Boolean).join(" "),
  );
  if (name) await supabase.auth.updateUser({ data: nameMetadata(name) });
  return true;
}

/** Returns false when the user closed the browser. */
export async function signInWithGoogle(): Promise<boolean> {
  requireConfig();
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: AUTH_CALLBACK_URL, skipBrowserRedirect: true },
  });
  if (error || !data.url) throw new AuthError(error?.message ?? "Couldn't start Google sign-in.");
  const result = await WebBrowser.openAuthSessionAsync(data.url, AUTH_CALLBACK_URL);
  if (result.type !== "success") return false;
  const { queryParams } = Linking.parse(result.url);
  const code = typeof queryParams?.code === "string" ? queryParams.code : null;
  const failure = typeof queryParams?.error_description === "string" ? queryParams.error_description : null;
  if (!code) throw new AuthError(failure ?? "Google sign-in didn't finish. Try again.");
  const exchanged = await supabase.auth.exchangeCodeForSession(code);
  if (exchanged.error) throw new AuthError(exchanged.error.message);
  return true;
}

const PENDING_NAME_KEY = "auth.pendingName";

/** Emails a sign-in code. The name is applied once the code is verified. */
export async function sendEmailCode(rawEmail: string, rawName: string, captchaToken: string | null): Promise<string> {
  requireConfig();
  const name = normalizeName(rawName);
  if (!name) throw new AuthError("Enter your full name.");
  const email = normalizeEmailInput(rawEmail);
  if (!email) throw new AuthError("Enter a valid email address.");
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      shouldCreateUser: true,
      emailRedirectTo: AUTH_CALLBACK_URL,
      data: nameMetadata(name),
      captchaToken: captchaToken ?? undefined,
    },
  });
  if (error) throw new AuthError(friendlyAuthError(error.message));
  await SecureStore.setItemAsync(PENDING_NAME_KEY, JSON.stringify({ email, name }));
  return email;
}

export function normalizeCode(code: string): string | null {
  const digits = code.replace(/\D/g, "");
  return digits.length === EMAIL_CODE_LENGTH ? digits : null;
}

export async function verifyEmailCode(email: string, rawCode: string): Promise<void> {
  requireConfig();
  const code = normalizeCode(rawCode);
  if (!code) throw new AuthError(`Enter the ${EMAIL_CODE_LENGTH}-digit code from your email.`);
  const { data, error } = await supabase.auth.verifyOtp({ email, token: code, type: "email" });
  if (error) throw new AuthError(friendlyAuthError(error.message));
  if (!data.session) throw new AuthError("We verified the code but couldn't start a session. Request a new code and try again.");
  const pending = await SecureStore.getItemAsync(PENDING_NAME_KEY);
  if (pending) {
    const { email: pendingEmail, name } = JSON.parse(pending) as { email: string; name: string };
    if (pendingEmail === email) await supabase.auth.updateUser({ data: nameMetadata(name) });
    await SecureStore.deleteItemAsync(PENDING_NAME_KEY);
  }
}

/** Local Docker stack only: the seeded users have a fixed password. */
export async function signInWithLocalPassword(email: string, password: string) {
  if (!config.isLocalBackend) throw new AuthError("Password sign-in is only for the local development stack.");
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new AuthError(error.message);
}

function friendlyAuthError(message: string): string {
  if (/token has expired|invalid/i.test(message)) return "That code is wrong or has expired. Request a new one.";
  if (/rate limit|too many/i.test(message)) return "Too many attempts. Wait a minute, then try again.";
  if (/captcha/i.test(message)) return "The security check failed. Try again.";
  return message;
}

/**
 * Signs out and removes this account's data from the phone. Unsynced local
 * changes are lost, so callers confirm first when there are any.
 */
export async function signOut(session: { userId: string; store: Store; sync: SyncEngine }) {
  await unregisterPushDevice(session.userId).catch(() => undefined);
  await wipeLocal(session);
  const { error } = await supabase.auth.signOut();
  // Signing out must work offline: drop the saved session even when the
  // server can't be told.
  if (error) await supabase.auth.signOut({ scope: "local" });
}

/** Deletes the account on the server, then signs out locally. */
export async function deleteAccount(session: { userId: string; store: Store; sync: SyncEngine }) {
  const { error } = await supabase.functions.invoke("delete-account", { method: "POST" });
  if (error) throw new AuthError("Couldn't delete your account. Check your connection and try again.");
  await wipeLocal(session);
  await supabase.auth.signOut({ scope: "local" });
}

async function wipeLocal({ userId, store, sync }: { userId: string; store: Store; sync: SyncEngine }) {
  sync.stop();
  await store.close();
  await deleteStore(userId);
  const receipts = new Directory(Paths.document, "receipts");
  if (receipts.exists) receipts.delete();
}
