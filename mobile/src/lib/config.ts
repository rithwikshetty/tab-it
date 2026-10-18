// Build-time configuration. Expo inlines EXPO_PUBLIC_* variables when it
// bundles, from `.env.development.local` for development builds and
// `.env.production.local` (or EAS environment variables) for release builds.
// Nothing falls back to a hosted project: a build without a backend shows a
// configuration error instead of silently pointing somewhere else.

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL?.trim() ?? "";
const supabaseKey = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";
const turnstileSiteKey = process.env.EXPO_PUBLIC_TURNSTILE_SITE_KEY?.trim() ?? "";

export const BUNDLE_ID = "com.rithwikshetty.tab";
export const AUTH_CALLBACK_URL = `${BUNDLE_ID}://auth-callback`;
export const INVITE_URL_PREFIX = "https://tab-it.app/join/";
export const PRIVACY_URL = "https://tab-it.app/privacy";

export const config = {
  supabaseUrl,
  supabaseKey,
  turnstileSiteKey: turnstileSiteKey || null,
  isConfigured: supabaseUrl.length > 0 && supabaseKey.length > 0,
  /** A local Supabase stack (Docker) rather than a hosted project. */
  isLocalBackend: /^http:\/\/(127\.0\.0\.1|localhost|10\.0\.2\.2)(:\d+)?/.test(supabaseUrl),
};
