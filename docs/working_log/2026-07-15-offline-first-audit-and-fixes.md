# Offline-first audit and fixes

## Goal

User report: with internet off, the app sometimes never gets past the initial splash animation. Audit the whole app for offline-first violations, fix them end to end, and remove anything that doesn't align with offline-first.

## 2026-07-15 — Audit findings

Read the full boot/auth/sync surface (TabApp, AppShell, RootView, AuthService, SyncService, RealtimeService, ReceiptStorage, screens) plus the vendored supabase-swift 2.46.0 source to confirm SDK semantics.

**The data layer is already offline-first.** All writes (expenses, settlements, trips, mutes, activity-seen) save to SwiftData first, mark rows dirty via `pushedWriteID != writeID`, and push opportunistically. Pull failures are treated as "remote unknown" and never delete local rows. Receipts persist to a local pending-upload file. No changes needed there.

**Finding 1 (the reported bug, critical): expired session at launch blocks on the network and can wipe local data.**
`AuthService.observeAuthState()` special-cases `.initialSession` with an expired access token: it holds `phase = .loading` (splash stays up indefinitely) and calls `client.auth.session`, which performs a network token refresh. Offline, that throws a network error → `enterSignedOut()` → `LocalStore.wipe` destroys all local data. An access token expires after ~1 hour, so any launch offline after >1h away hits this.

Verified in supabase-swift 2.46.0 source (SessionManager.swift, APIClient.swift):
- Network refresh failure just throws; the persisted session is kept and auto-refresh retries. No signedOut.
- Definitive revocation (session_not_found, session_expired, refresh_token_not_found, refresh_token_already_used) → the SDK itself removes the session and emits `.signedOut` via authStateChanges — which our observer already handles.

So the offline-first fix is to trust the persisted session immediately (sign in from `session.user` even when expired) and delete `resolveExpiredInitialSession()` + the `.loading` special case entirely. Revoked tokens still sign out correctly via the SDK's own event.

**Finding 2: sync gating goes dead when the token is expired, even online.**
`SyncService.hasRealSession` requires `!session.isExpired`. Launching online with an expired token: the boot-task `pushPending`/`pullAll` silently no-op, and nothing re-triggers after auto-refresh succeeds. Fix: resolve the session with `try await client.auth.session` (refreshes when needed; throws offline) instead of gating on `isExpired`.

**Finding 3: no sync retrigger when connectivity returns.**
Writes made offline sit until the next cold launch, foreground, or user save. Foreground catch-up only pulls (`pullAll`), never pushes. Fix: NWPathMonitor in SyncService — on regaining connectivity, push then pull; and add `pushPending()` to the scenePhase foreground catch-up in RootView.

**Finding 4: receipts attached offline can't be viewed.**
Receipt bytes are saved to the local pending-upload file, but ExpenseDetailView / ExpenseEntryView always display via a network `createSignedURL`. Fix: fall back to the local pending file when it exists.

**Finding 5: misleading offline errors.**
Flows that genuinely need the server (add person by email, non-group container resolve, person email update/remove) throw `SyncError.signInRequired` ("Sign in to sync this trip.") when the real problem is no connectivity. Fix: distinguish an `offline` error when a persisted session exists but can't be resolved.

Judged out of scope (keeping it simple): offline queuing for the server-identity RPC flows (add person, non-group containers — server-assigned identity, honest error instead), receipt download caching, offline banner UI.

## 2026-07-15 — Direction

Implementation routed to Codex (one job, full spec) per architect/implementer split; no new files (project has no file-system-synchronized groups, avoiding pbxproj edits). Claude reviews the diff, then builds + runs tests.

## 2026-07-15 17:32 BST — Implementation

Removed the expired-initial-session network gate so persisted users enter the app immediately, and changed sync session gating to resolve `client.auth.session` asynchronously. Server-required flows now distinguish an unresolved persisted session as offline while preserving sign-in-required behavior when no session exists.

Added connectivity-restored and foreground push-then-pull catch-up. Pending receipt files are now exposed for local display and preferred before requesting a signed storage URL. No tests referenced the removed auth helper or the old session gate, so no test source changes were needed.

## 2026-07-15 17:37 BST — Validation

`git diff --check` passed. All six changed Swift source files passed Swift 6 parsing, and the strict-concurrency `NWPathMonitor` callback shape type-checked independently.

The requested Xcode build and TabTests commands both stopped during package-graph resolution before compiling code because the managed workspace cannot write Xcode's normal caches. Redirecting caches and DerivedData to `/private/tmp` advanced to SwiftPM manifest evaluation, but nested `sandbox-exec` is also prohibited by the environment. CoreSimulator was unavailable for the same sandbox reason, so a full simulator build and test run could not be completed here.

## 2026-07-15 17:45 BST — Independent validation (Claude, main session)

Reviewed the full diff against the spec — all six files match, no deviations. Ran validation outside the Codex sandbox: `xcodebuild build` on iPhone 17e (iOS 26.5) — BUILD SUCCEEDED; `-only-testing:TabTests test` — 90 tests in 18 suites passed; mock-auth simulator smoke launch boots past the splash into the Trips list.

Note: five working-tree files (ExpenseRow, EntityViewState, FriendsPresenter, ViewState, ExpenseDatesTests — a balanceLabel → netAmount/totalAmount change) were already modified before this job and are unrelated concurrent work; they compile and pass tests together with these changes but are not part of the offline-first fix.
