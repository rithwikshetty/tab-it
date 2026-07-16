# Trip invite links (share link to join a group)

## Goal

Let a trip member share a link that gets anyone into the trip: tap link, app
opens (App Store landing page if not installed), sign in if needed, and the
signed-in user becomes a trip member and lands on the trip. No "which one are
you" claim screen — the link is just an authenticated door into the trip.
Email pre-add + auto-claim stays unchanged; the link complements it.

Decisions from discussion (see docs/research/2026-07-16-member-joining-standards.md):

- Per-trip secret token, revocable (Settle Up's inviteLinkActive pattern).
- Joiner is added as themselves; duplicates possible if they were pre-added
  under a different email — accepted; manual fix via update_trip_person_email.
- Canonical URL: https://tab-it.app/join/<token>. Domain not yet purchased, so
  universal links can't be verified end to end yet; app also handles a
  tab:// scheme for development.
- DB changes applied additively to the shared prod DB (real data live) — no
  destructive reset.

## Log

### 2026-07-16 — start

Plan: DB layer first (invite storage, get-or-create/revoke/join RPCs, RLS,
privileges, pgTAP), rebuild baseline, apply additively via Supabase MCP, then
delegate app-side share/join flow to Codex with a spec. Landing page + AASA
as static files ready for hosting.

### 2026-07-16 — DB layer done, applied to remote

- New `supabase/sql/21_trip_invites.sql`: trip_invites table (one active
  128-bit hex token per trip, revocable, member-only select, all writes via
  RPC), get_or_create_trip_invite, revoke_trip_invite, join_trip_with_invite.
  Join semantics: existing member -> restore/no-op; pending row matching auth
  email -> claim in place (keeps ledger identity, restores if removed);
  otherwise fresh member row. Baseline rebuilt, assembly check ok.
- pgTAP suite supabase/tests/15_trip_invites.sql (30 assertions) passes
  against the remote DB. Gotcha found: temp tables read under `set local role
  authenticated` need explicit grants.
- Applied additively to prod project gaseuxsieddlksxtdliq via MCP
  apply_migration ("trip_invites"). No teardown; Thailand 2026 untouched.
- Found pre-existing failure in supabase/tests/08_activity_notifications.sql,
  unrelated to invites: commit 8013bac changed mark_activity_seen to
  mark_activity_seen(timestamptz default null) and bounded unread counts by
  joined_at, but the test still asserts the zero-arg signature and the old
  unread semantics (wants 6, gets 0). Needs a test update in a separate task.
- web/ added: join.html landing page + AASA template + README. TEAMID/BUNDLEID
  and App Store URL are placeholders; blocked on domain purchase + app
  publication.

### 2026-07-16 — app-side mapping + Codex delegation

- Explore agent mapped integration points: only URL entry today is the auth
  callback onOpenURL in TabApp.swift; no universal-link handling exists.
  Navigation is RootView-owned NavigationStack path arrays; the push-tap
  handler (RootView.handlePushTap) is the pattern to mirror for post-join
  navigation. All direct RPCs no-op under mock auth via resolveRealSession.
- AASA filled in with real IDs (KR8C647GCW.com.rithwikshetty.tab).
- Delegated app implementation to Codex (workspace-write): InviteLinkService
  (parse/persist pending token), onOpenURL + onContinueUserActivity entry,
  SyncService joinTripWithInvite/tripInviteURL/revokeTripInvite + DTOs,
  RootView join/drain flow (warm tap + post-sign-in), TripDetailView share +
  revoke menu items, associated-domains entitlement, parser unit tests.

### 2026-07-16 07:20 BST — app implementation started

- Read the plain-writing guide and inspected the current auth callback, sync
  RPC, navigation, trip menu, entitlement, test, and Xcode project patterns.
- Existing Supabase, research, web, and working-log changes are being preserved.
  App work is limited to the invite-link feature.
- Added the persisted invite URL parser service and its pure Swift Testing
  coverage first. Integration wiring and validation are next.

### 2026-07-16 07:32 BST — app implementation complete, simulator blocked

- Added invite RPC DTOs and SyncService methods, URL capture for custom and
  universal links, the signed-in join drain and guarded trip navigation, the
  trip-menu share/revoke controls, and the associated-domain entitlement.
- Registered InviteLinkService.swift and InviteLinkParsingTests.swift in the
  generated Xcode project. The project plist and entitlement plist both pass
  `plutil -lint`, all changed Swift files pass `swiftc -parse`, and
  `git diff --check` passes.
- Tried the requested generic iOS Simulator build and the focused TabTests run
  on the existing iPhone 17 Pro simulator. This managed environment cannot
  connect to CoreSimulatorService and rejects SwiftPM's nested `sandbox-exec`
  while resolving package manifests, so both xcodebuild commands stop before
  compilation or test execution. No real-auth join was attempted.

### 2026-07-16 — app side landed, verified

- Codex implemented the app side per spec; I reviewed the full diff and
  independently re-ran the build + InviteLinkParsingTests (6/6 pass on
  iPhone 17 Pro sim). pbxproj registration confirmed (xcodeproj is gitignored
  by design, so it never shows in git status).
- Flow as built: link tap (universal or custom scheme) -> InviteLinkService
  persists token -> RootView joins via RPC (warm onChange or post-sign-in
  drain after claim, before pullAll) -> pullAll -> navigate to trip with the
  push-tap base guard. Offline keeps the token pending; invalid/revoked shows
  an alert and drops it. TripDetailView menu: Share invite link (fetch, then
  UIActivityViewController) + Turn off invite link (confirmation dialog).
- Known follow-ups: 22023 (no verified email) currently shows the
  invalid-link copy; real-auth end-to-end smoke test still needed (mock auth
  no-ops all RPCs); universal links inert until tab-it.app hosts the AASA;
  custom scheme com.rithwikshetty.tab://join/<token> works for dev testing.

### 2026-07-16 — site/ reconciliation

Correction: tab-it.app is already owned and the site is already live on
Vercel (project "tab-it", source site/). The earlier web/ folder duplicated
that, so it's gone. join.html rebuilt in the site's cork-board style and
placed in site/, AASA moved to site/.well-known/, vercel.json gained the
/join/:token rewrite and the AASA content-type header. Universal links start
working on the next site deploy; the App Store button on join.html still
needs the real URL once the app is published.
