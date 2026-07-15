# Notification system end-to-end review and fixes

## Goal

Rithwik asked for a full review of the notification system — push banners,
badges, taps, the in-app Activity feed, native iOS behavior end-to-end — with an
independent Codex review, and to fix any real bugs found.

## 2026-07-14 — architecture traced

DB write → `activity_log` trigger (09) → pg_net webhook (18) → `send-push` edge
function → APNs (badge stamped per-recipient via `unread_activity_count`).
Device: `PushAppDelegate` → `PushService` → `RootView` (token upsert, tap
deep-link, local badge) + Activity feed with `activity_last_seen_at` cursor and
per-row local read state. Verdict on the architecture itself: sound.

## 2026-07-14 — bugs found (own pass) and fixed

1. **Sign-out leaked push registrations (privacy).** Sign-out wiped local data
   but left the `push_devices` row, so the device kept getting the old
   account's banners; a second account on the same phone would get both.
   Fixes: `AuthService.onWillSignOut` → `SyncService.unregisterPushDevice`
   (deletes the row while the session is still valid), and registration moved
   to a new `register_push_device` security-definer RPC that releases the
   token from other accounts (RLS blocks the client from doing it). SQL in
   `supabase/sql/10_push_devices_mutes.sql`; `PushDeviceInsertDTO` removed.
2. **Cold-start notification tap did nothing.** `PushService.lastTap` was set
   before `RootView` existed; `.onChange` never fired. RootView now consumes a
   pending tap at the end of its startup task.
3. **Tap on a not-yet-synced entity landed on the trip, not the detail.**
   `handlePushTap` now pulls first when the entity isn't local, then appends
   the detail route only if the user hasn't navigated away.
4. **`ExpiredProviderToken` dropped the push.** `apns.ts` now retries the send
   once with a freshly minted JWT (split into `sendPush` wrapper + `sendOnce`).

## 2026-07-14 — deployment (with Rithwik's explicit go-ahead)

- Verified prod data before/after: 3 trips, 59 expenses, 6 settlements,
  10 trip_people, 85 activity rows, 9 push_devices — identical.
- Applied migration `register_push_device_rpc` (create function + grants only)
  to project `gaseuxsieddlksxtdliq` via Supabase MCP.
- Rebuilt baseline (`build_schema.sh --write`) and ran `00_sql_assembly.sh` — ok.
- Deployed `send-push` v5 (verify_jwt still false; shared-secret auth unchanged).

## Open

- Codex independent review still running; findings to be reconciled when it
  reports back.
- App-side changes (sign-out dereg, RPC registration, tap fixes) ship with the
  next build; current build's direct upsert keeps working meanwhile.

## 2026-07-14 — Codex findings reconciled

Codex confirmed the four earlier fixes and the overall architecture, and raised
11 findings. Verified and fixed in this pass:

- **#1 cursor never pulled (HIGH, confirmed):** `visible_profiles` and the
  column grants hide `activity_last_seen_at`, so fresh installs badge all
  history unread. Added self-only `activity_read_cursor()` RPC; `pullProfiles`
  merges it forward.
- **#2 account-switch token miss (HIGH, confirmed):** same APNs token across
  accounts means `.onChange(of: deviceToken)` never fires. RootView now
  registers explicitly after startup auth; the register RPC steals the token.
- **#3 fan-out fragility (partial):** per-target try/catch in send-push so one
  bad token/network throw can't abort remaining recipients. Durable outbox
  with backoff deliberately deferred.
- **#4 read acks not durable (confirmed):** pending seen-at persisted in
  UserDefaults, retried from `pushPending`; `mark_activity_seen(p_seen_at)`
  clamps to server clock (also fixes client clock-skew over-advance).
- **#6 pre-join history unread (confirmed):** `unread_activity_count` and
  `ActivityPresenter.isUnread` now bound by `joined_at`; regression test added.
- **#7 foreground receipt (confirmed):** `willPresent` publishes the payload;
  RootView triggers a pull so the feed matches the banner.
- **#8 permission flip needs relaunch (confirmed):** `registerIfAuthorized()`
  on foreground (never prompts).
- **#9 stale badge after sign-out (confirmed):** badge zeroed in onSignedOut.
- **#10 partial:** `apns-expiration` now +24h. Per-device APNs env deferred.
- **#11 partial:** edge function now loads the canonical activity row by ID and
  ignores caller-supplied content (anti-spoof). Replay dedupe deferred.

Deferred (design work, not bugs to patch): durable push outbox/retries, badge
reordering reconciliation beyond on-open recompute (#5), per-event server read
state, per-device APNs environment routing.

**Operational discovery:** `private.app_config` in prod is EMPTY — no
`push_webhook_url`/secret seeded, so the activity trigger no-ops and no push
has ever been sent in prod. APNs edge-function secrets likely unset too.
Blocked on Rithwik: seed config, set APNS_* + WEBHOOK_SECRET function secrets.

Local validation: swiftc -parse clean on all edited files; baseline rebuilt;
SQL assembly test ok. Pending approval: migration (mark_activity_seen
signature + activity_read_cursor + unread_activity_count) and send-push v6.

## 2026-07-14 — second migration + send-push v6 deployed (approved)

- Applied `activity_cursor_and_joined_bound` to prod: dropped zero-arg
  mark_activity_seen, created mark_activity_seen(p_seen_at default null),
  activity_read_cursor(), and the joined_at-bounded unread_activity_count.
- Data verified unchanged (3/59/6/10/85/9); exactly one mark_activity_seen
  overload remains; cursor function present.
- Deployed send-push v6 (canonical-row fetch, per-target error isolation,
  apns-expiration +24h). verify_jwt still false.
- Remaining to go live: seed private.app_config (push_webhook_url +
  push_webhook_secret) and set APNS_* / WEBHOOK_SECRET function secrets —
  the .p8 key must come from Rithwik's Apple Developer account.

## 2026-07-15 — push pipeline armed in prod

- APNs key created in Apple Developer portal (tabit APNs, Key ID ADL6269Z26).
  .p8 stored at Apps/Tab/Config/ (covered by the existing *.p8 gitignore rule).
- Set edge function secrets: APNS_TEAM_ID, APNS_KEY_ID, APNS_BUNDLE_ID
  (com.rithwikshetty.tab), APNS_P8_KEY, and a fresh WEBHOOK_SECRET (APNS_ENV
  was already sandbox from June).
- Re-seeded private.app_config with push_webhook_url + matching secret — this
  had been wiped by an earlier destructive DB reset; remember it dies with
  every reset and must be re-seeded.
- Pipeline now fully configured: activity trigger → pg_net → send-push v6 →
  APNs sandbox. Remaining: real-device test.
