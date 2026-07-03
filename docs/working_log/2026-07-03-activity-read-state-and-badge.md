# Activity feed: per-row read state, swipe to mark read, badge fixes

**Goal:** User reports the Activity tab badge is stuck at 5: opening the tab (or a
notification row) doesn't clear it, and there is no swipe-to-mark-read. Diagnose and fix.

## 2026-07-03 — Diagnosis

Read `ActivityView.swift`, `ActivityPresenter.swift`, `RootView.swift`,
`SyncService.markActivitySeen`, `SyncMerge.apply(ProfileDTO)`.

Three findings:

1. **One-shot mark-seen.** `ActivityView.onAppear` guards on `displaySince == nil`
   (guard added so pop-back from a detail doesn't wipe highlights). Side effect:
   `markActivitySeen()` runs only on the *first* tab visit per app session. Any
   activity arriving after that never gets marked seen on later visits — badge
   stays stuck.
2. **Cursor clobber race.** `markActivitySeen()` sets `activityLastSeenAt`
   locally without bumping `updatedAt`/`writeID`, so the profile row stays
   "clean" under the LWW merge. `pullProfiles` (fired concurrently by the tab's
   `.task { pullAll() }`) then overwrites the local cursor with the server's
   stale value. If the RPC fails (offline), the cursor reverts entirely.
3. **No per-row read state.** Unread is purely `timestamp > cursor`. Tapping a
   row cannot decrement the count; feed is a custom ScrollView/Card, so no
   native swipe actions exist.

## 2026-07-03 — Decision

Adopt an inbox model instead of the pure cursor model:

- Add local-only `readAt: Date?` to `ActivityEntity` (server `activity_log` is
  append-only; no schema/server change).
- Unread = `actorID != me && !muted && readAt == nil && timestamp > cursor`.
  Cursor stays as the cross-device floor.
- Tap on a row marks it read. Trailing swipe: "Mark as read". Toolbar: "Mark
  all read" (sets `readAt` on all + advances the server cursor via
  `mark_activity_seen`).
- Opening the tab no longer auto-clears everything; reading does.
- Fix the clobber: profile merge takes `max(local, remote)` for
  `activityLastSeenAt` (cursor is monotonic).
- Convert the feed to a `List` to get native `swipeActions`, preserving the
  Sage card look.

Implementation delegated to Codex (workspace-write) with this spec; review,
build, tests, and simulator verification stay with the main session.

## 2026-07-03 07:01:19 BST

- Started scoped Activity inbox/read-state rework. Initial scan found existing ActivityEntity, ActivityPresenter, ActivityView, SyncMerge, SyncService, and ActivityPresenterTests as the files to change.

## 2026-07-03 07:01:58 BST

- Added local ActivityEntity.readAt and updated ActivityPresenter unread logic to require other actor, unmuted trip, nil readAt, and timestamp newer than cursor.
- Updated profile cursor merge and markActivitySeen to keep activityLastSeenAt monotonic while marking unread activity rows read locally.

## 2026-07-03 07:03:26 BST

- Reworked ActivityView from ScrollView/Card groups to List sections with row tap read marking, unread-only trailing swipe actions, and a conditional Mark all read control. Opening Activity no longer marks rows read.
- First xcodebuild test attempt failed before compilation because the sandbox could not write Xcode/SwiftPM caches under the user home and CoreSimulatorService was unavailable. Retried with DerivedData and module caches under /private/tmp; SwiftPM still attempted diagnostics under ~/Library/Caches and failed before compilation.

## 2026-07-03 07:03:43 BST

- A further generic iOS Simulator build attempt with DerivedData, PackageCache, HOME, and module caches under /private/tmp still failed before compilation at sandbox-exec: sandbox_apply: Operation not permitted. simctl also cannot list devices because CoreSimulatorService is disconnected.

## 2026-07-03 07:03:49 BST

- Ran git diff --check successfully. No xcodegen run was needed because no files were added to the Xcode project.

## 2026-07-03 07:35 BST — Review, hardening, validation

- Reviewed Codex's diff. Logic correct; two cleanups applied in the main
  session: `ActivityView` was running the presenter twice per render
  (`unreadRowIDs` computed property re-derived `sections` despite the hoist),
  now derived from the hoisted value; and the hand-rolled title/`Mark all read`
  header now reuses `LargeTitle`, which gained an optional trailing slot
  (default `EmptyView`, existing call sites unchanged).
- Made `DebugActivitySeed` wipe-and-reseed (rows + profile cursor) under
  `TAB_SEED_ACTIVITY=1` instead of guarding on an empty store, so seeded
  launches are deterministic for manual runs and UI tests.
- Added `ActivityFlowUITests.swift` (XCUITest, matching the existing UI-test
  pattern): seeded launch shows the mark-all control, swipe → "Mark as read"
  clears one row, "Mark all read" clears the rest, and a relaunch without the
  seed flag confirms read state persists. Ran `xcodegen` for the new file.
- Validation: full suite green — 84 TabTests + 11 TabUITests (including the
  new Activity flow test) on iPhone 17 simulator. Visual check via simulator
  screenshots: seeded feed renders with card styling intact, unread dots,
  tab badge 5, "Mark all read" in the header.
- Nothing committed; changes left in the working tree.

## 2026-07-03 07:55 BST — Swipe-to-delete added

- User confirmed the inbox direction and asked for swipe-to-delete in the
  opposite direction from mark-as-read. Implemented Mail-style edges:
  leading swipe (right) = "Mark as read" (unread rows only), trailing swipe
  (left) = "Delete", both with full-swipe enabled.
- Delete is a device-local dismissal, not a row deletion: `activity_log` is
  re-pulled on every sync and a genuinely deleted local row would be
  re-inserted. New `ActivityEntity.dismissedAt` hides the row from the feed
  (and from the unread count) permanently; the 90-day activity window purge
  eventually drops the stored row. Dismissing an unread row also marks it
  read so the badge stays consistent.
- Presenter filters dismissed rows out of sections and unread; new unit test
  covers both. UI test extended: swipe-read on the leading edge, swipe-delete
  on the trailing edge, mark-all, and relaunch persistence (deleted row does
  not come back).
- Validation: 85 TabTests + ActivityFlowUITests green on iPhone 17 simulator.

## 2026-07-03 08:50 BST — Rewrap glitch fixed; auto-read replaces Mark all read

- User reported the row text "loses its breaks" after swipe-to-mark-read.
  Reproduced with a throwaway XCUITest capturing before/after screenshots:
  the unread style (semibold title + dot occupying layout) made
  "Cy deleted Duplicate lunch" wrap to two lines; marking read flipped to
  regular weight and removed the dot, so the same text re-fit one line and
  the row visibly snapped mid-swipe-settle.
- Fix: unread styling is now metric-stable. Title weight is constant
  (.medium); unread is signalled by a Sage.accentTint row background plus the
  dot, whose slot is always reserved (opacity fade). Read/unread flips can no
  longer change text layout. Mutations wrapped in withAnimation. Verified
  with a second before/after capture: text identical across the flip.
- Also per user direction: removed the "Mark all read" button. Unread rows
  stay highlighted while viewing the Activity tab; leaving it (tab switch or
  pushing a detail) auto-marks everything read via onDisappear →
  markActivitySeen (guarded so it only fires when something is unread).
  LargeTitle reverted to its original no-trailing-slot form.
- Rows expose read state via accessibilityValue ("Unread"/"Read") — an
  actual VoiceOver improvement (unread was visual-only) and a stable hook for
  the UI test, whose earlier swipe-probe on a read row fell through to a tap
  and navigated into the seed's fake trip ("Trip not found").
- Validation: 85 TabTests + 11 TabUITests green, including the reworked
  ActivityFlowUITests (swipe-read, swipe-delete, auto-read on tab leave,
  relaunch persistence). Scratch diagnostic test deleted.
