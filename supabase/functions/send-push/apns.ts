// Direct APNs over HTTP/2 using token-based auth (.p8 key) — no third-party SDK.
// WebCrypto ES256 returns a raw r||s (JOSE) signature directly: NO DER conversion.
// Deno's native fetch negotiates HTTP/2 to APNs automatically.

const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";   // 10 chars -> iss
const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";     // 10 chars -> kid
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? ""; // apns-topic
const P8_PEM = Deno.env.get("APNS_P8_KEY") ?? "";     // full -----BEGIN PRIVATE KEY----- PEM
const PRODUCTION = (Deno.env.get("APNS_ENV") ?? "sandbox").toLowerCase() === "production";

export function apnsConfigured(): boolean {
  return TEAM_ID !== "" && KEY_ID !== "" && BUNDLE_ID !== "" && P8_PEM !== "";
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const b64urlStr = (s: string) => b64url(new TextEncoder().encode(s));

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

let cachedKey: CryptoKey | null = null;
let cachedJwt: { token: string; iat: number } | null = null;

async function getKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  try {
    cachedKey = await crypto.subtle.importKey(
      "pkcs8",
      pemToDer(P8_PEM),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
  } catch (e) {
    throw new Error(
      `Invalid APNS_P8_KEY (expected a PKCS#8 .p8 PEM): ${e instanceof Error ? e.message : String(e)}`,
    );
  }
  return cachedKey;
}

// Mint once, reuse ~50 min (Apple rejects iat older than 1h; reuse to avoid 429).
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000); // seconds, never ms
  if (cachedJwt && now - cachedJwt.iat < 50 * 60) return cachedJwt.token;
  const header = b64urlStr(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = b64urlStr(JSON.stringify({ iss: TEAM_ID, iat: now })); // no exp
  const data = new TextEncoder().encode(`${header}.${claims}`);
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await getKey(), data),
  );
  const token = `${header}.${claims}.${b64url(sig)}`;
  cachedJwt = { token, iat: now };
  return token;
}

export interface SendResult {
  ok: boolean;
  status: number;
  reason?: string;
  tokenDead: boolean; // 410 / BadDeviceToken / Unregistered -> delete the token
}

export async function sendPush(
  deviceToken: string,
  payload: unknown,
  opts?: { collapseId?: string },
): Promise<SendResult> {
  const first = await sendOnce(deviceToken, payload, opts);
  // The cached JWT can age past Apple's 1h window between mints; sendOnce
  // already dropped it, so one retry re-signs instead of losing the push.
  if (!first.ok && first.reason === "ExpiredProviderToken") {
    return await sendOnce(deviceToken, payload, opts);
  }
  return first;
}

async function sendOnce(
  deviceToken: string,
  payload: unknown,
  opts?: { collapseId?: string },
): Promise<SendResult> {
  const host = PRODUCTION ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const headers: Record<string, string> = {
    authorization: `bearer ${await providerToken()}`,
    "apns-topic": BUNDLE_ID,
    "apns-push-type": "alert",
    "apns-priority": "10",
    // Without this, APNs stores undeliverable pushes for up to 30 days — a
    // week-old "added Dinner" banner (with a stale badge) helps no one.
    "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 60 * 60),
    "content-type": "application/json",
  };
  if (opts?.collapseId) headers["apns-collapse-id"] = opts.collapseId;

  const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  if (res.status === 200) return { ok: true, status: 200, tokenDead: false };

  const body = await res.json().catch(() => ({} as Record<string, unknown>));
  const reason = (body.reason as string) ?? "Unknown";
  if (reason === "ExpiredProviderToken") cachedJwt = null; // force re-mint next call
  const tokenDead = res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered";
  return { ok: false, status: res.status, reason, tokenDead };
}
