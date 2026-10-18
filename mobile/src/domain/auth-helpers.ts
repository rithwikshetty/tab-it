import { nameCharacters } from "./presentation-helpers";
export function normalizedAuthEmail(email: string | null): string | null {
  return email?.trim().toLowerCase() || null;
}
export function isApplePrivateRelayEmail(email: string | null): boolean {
  return (
    normalizedAuthEmail(email)?.endsWith("@privaterelay.appleid.com") ?? false
  );
}
export function visibleEmail(email: string | null): string | null {
  return isApplePrivateRelayEmail(email) ? null : normalizedAuthEmail(email);
}
export function normalizedDisplayName(name: string | null): string | null {
  return name?.trim()
    ? nameCharacters(name.trim()).slice(0, 60).join("")
    : null;
}
export function fallbackDisplayName(email: string | null): string {
  if (!email || isApplePrivateRelayEmail(email)) return "You";
  const prefix = nameCharacters(
    email.split("@").filter(Boolean)[0]?.trim() ?? "You",
  )
    .slice(0, 60)
    .join("");
  return prefix
    ? prefix
        .toLowerCase()
        .replace(/\p{L}[\p{L}\p{M}]*(?:['’][\p{L}\p{M}]+)*/gu, (word) => {
          const letters = [...word];
          const upper = letters[0]!.toUpperCase();
          const titleDigraphs: Record<string, string> = {
            Ǆ: "ǅ",
            Ǉ: "ǈ",
            Ǌ: "ǋ",
            Ǳ: "ǲ",
          };
          const title =
            titleDigraphs[upper] ?? upper[0]! + upper.slice(1).toLowerCase();
          return title + letters.slice(1).join("");
        })
    : "You";
}
export const emailVerificationCodeLength = 8;
export function normalizedVerificationCode(code: string | null): string | null {
  const digits = code?.replace(/[^\p{N}]/gu, "") ?? "";
  return [...digits].length === emailVerificationCodeLength ? digits : null;
}
export function isExpectedAuthCallbackURL(
  rawURL: string,
  scheme: string,
): boolean {
  try {
    const url = new URL(rawURL);
    return (
      url.protocol === scheme + ":" &&
      url.hostname === "auth-callback" &&
      (url.pathname === "" || url.pathname === "/")
    );
  } catch {
    return false;
  }
}
export function inviteToken(rawURL: string, scheme: string): string | null {
  try {
    const url = new URL(rawURL),
      parts = url.pathname.split("/").filter(Boolean);
    let token: string | undefined;
    if (
      url.protocol === "https:" &&
      ["tab-it.app", "www.tab-it.app"].includes(url.hostname.toLowerCase()) &&
      parts.length === 2 &&
      parts[0] === "join"
    )
      token = decodeURIComponent(parts[1]!);
    else if (
      url.protocol.toLowerCase() === scheme.toLowerCase() + ":" &&
      url.hostname.toLowerCase() === "join" &&
      parts.length === 1
    )
      token = decodeURIComponent(parts[0]!);
    return token && /^[0-9a-f]{32}$/i.test(token) ? token.toLowerCase() : null;
  } catch {
    return null;
  }
}
