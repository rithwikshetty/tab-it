# ADR-0002: Notification architecture

## Status

Accepted — 2026-06-05

## Context

tab needs notifications: when anyone does something on a trip (adds/edits/deletes an expense or settlement, joins, etc.), every *other* member should be told — both as an OS-level push when the app is closed, and in an in-app inbox they can browse. CLAUDE.md already lists three dormant tables for this (`activity_log`, `push_devices`, `trip_mute_prefs`) but nothing reads or writes them: no triggers, no edge functions, no client registration, no push entitlement. Realtime is currently-viewed-trip only, so it cannot reach a member who isn't looking at that trip.

The user's framing was "however Apple operates, nothing out of the box" — i.e. the Apple-native path, no third-party push aggregator and no bespoke delivery scheme.

Two questions had to be answered before any code: **what is the source of truth for "something happened,"** and **how does a push physically get sent.** Both are backbone choices — expensive to change once devices are registered and history exists — so they are recorded here.

## Decision

Treat notifications as **one event stream rendered through two channels**: the in-app [[Activity]] feed and the [[Push notification]] channel both read from a single source.

### Event sourcing — shared row, written by DB triggers

- The single source of truth is the existing append-only `activity_log` (one row per event, **not** one row per recipient).
- Rows are written **server-side by database triggers** on `expenses`, `settlements`, `trip_people`, and `trips`. The trigger records `actor_id = auth.uid()`, the action, the entity, and a `snapshot_json` (actor name, trip name, and type-specific fields for offline rendering + push text).
- Triggers are **idempotent against offline re-syncs**: because `set_sync_fields` regenerates `write_id` on every write, `write_id` can't be the dedup key. Instead an UPDATE emits an event only when a *user-visible* column actually changed (`IS DISTINCT FROM` across amount/currency/description/etc.), so a no-op re-upsert produces nothing. Service-role/maintenance writes are skipped (`auth.uid()` null → no event).
- Targeting, self-exclusion, and read/unread are **derived per user at read time**, never duplicated into per-recipient rows:
  - In-app feed = `activity_log` rows for trips the user belongs to, `actor != me`, newest first.
  - Read state = a **single per-user `last_seen_at` cursor** (synced). Unread = events newer than the cursor on non-muted trips. Opening the Activity tab advances the cursor.

### Push delivery — DB webhook → edge function → direct APNs

- A Supabase **Database Webhook** on `activity_log` INSERT calls a new edge function (`supabase/functions/send-push/`).
- The edge function (service role, bypasses RLS):
  - computes recipients = trip members − actor − holders of a [[Trip mute preference]];
  - fetches those users' `push_devices` tokens;
  - signs an **ES256 JWT** with the APNs `.p8` auth key (Key ID, Team ID, bundle ID, APNs environment held as edge-function secrets);
  - POSTs to `api.push.apple.com` over HTTP/2, one request per token;
  - sets `aps.badge` to the recipient's current unread count so the app-icon badge is correct with the app closed;
  - sets `thread-id = trip id` (native iOS grouping) and `apns-collapse-id = entity id` for rapid re-edits;
  - deletes `push_devices` rows that APNs reports `410 Unregistered`.
- Banners are rich (actor + amount + description; trip name as title). Lock-screen privacy is delegated to iOS's native "Show Previews" setting — no custom privacy logic.
- Current policy: **every** action type pushes. This lives entirely in the sender and is tunable later without schema change.

### Client lifecycle

- Permission is requested on first launch after sign-in. The APNs token is re-registered and upserted on **every** launch, so reinstalls and token rotation self-heal. APNs never replays missed banners on reinstall; the synced feed carries the missed history instead.
- The Activity feed is a **local SwiftData mirror** (rolling window, paginate older on demand), so it works offline and the badge is a local query.

## Consequences

- `activity_log` joins the sync pull (a rolling ~90-day / 300-row window, pruned locally). `push_devices`, `trip_mute_prefs`, and the per-user `activity_last_seen_at` cursor (a column on `profiles`) join the sync push/pull in `SyncService`.
- New DB triggers across the mutable tables; a Database Webhook; one new edge function (the project's first — `supabase/functions/` is created here).
- App gains the `aps-environment` entitlement, an AppDelegate (`didRegisterForRemoteNotifications` + `UNUserNotificationCenterDelegate`), token upsert, deep-link handling for taps, and a `RootView` restructure to three tabs with per-tab `NavigationStack`s plus the Activity screen and tab/icon badge.
- A trip-mute toggle is added to the trip-detail overflow menu.
- Secrets to provision: APNs `.p8` key, Key ID, Team ID, bundle ID, APNs environment (sandbox for development builds, production for TestFlight and the App Store).

## Alternatives considered

- **Client writes the activity events.** The app inserts an `activity_log` row alongside each mutation and queues it in the offline sync. Rejected: every write path must remember; the offline queue must carry activity rows; dedupe is per-path; a buggy or old client can emit wrong/missing events. Triggers put it in one server-authoritative place.
- **Per-recipient fan-out.** Write one notification row per recipient per event for trivial per-row read state. Rejected: N× storage, fan-out logic on every write, and a second stream that drifts from `activity_log`. The shared row + read-time derivation is leaner and matches the existing schema.
- **Third-party push (OneSignal / Firebase FCM).** Less crypto plumbing, dashboards included. Rejected: adds an external dependency, shares trip data with a third party, and isn't the Apple-native path the product wants.
- **In-app burst-collapse now** ("Bo added 3 expenses"). Deferred: meaningful collapse-window/expand/read-state design for a burst pattern that's rare at friend-group scale. Native APNs grouping + in-app date headers cover the common case for free.
- **Catch-up summary push on reinstall.** Deferred: a custom behavior beyond standard iOS; the synced feed already restores missed history.
