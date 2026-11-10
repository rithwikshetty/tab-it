export function inviteToken(rawURL: string, scheme: string): string | null {
  try {
    const url = new URL(rawURL),
      parts = url.pathname.split("/").filter(Boolean);
    let token: string | undefined;
    if (
      (url.protocol === "https:" || url.protocol === "http:") &&
      ["tab-it.app", "www.tab-it.app"].includes(url.hostname.toLowerCase()) &&
      parts.length === 2 &&
      parts[0] === "join"
    )
      token = decodeURIComponent(parts[1]!);
    else if (url.protocol.toLowerCase() === scheme.toLowerCase() + ":" && url.hostname.toLowerCase() === "join" && parts.length === 1)
      token = decodeURIComponent(parts[0]!);
    return token && /^[0-9a-f]{32}$/i.test(token) ? token.toLowerCase() : null;
  } catch {
    return null;
  }
}
