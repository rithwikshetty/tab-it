# WS2 sync lifecycle fixes

## 2026-07-18 20:34 BST — Goal

Fix the six audited sync, realtime, authentication, activity-cursor, and receipt-upload lifecycle bugs without changing public call sites, contacting the live Supabase project, running simulator builds, or disturbing unrelated work. Add pure Swift Testing coverage where the concurrency and key-derivation logic has a useful test seam, then validate with the TabCore Swift package tests.

## 2026-07-18 20:36 BST — Initial inspection

Read the repository instructions, domain context, and current service implementations. Confirmed that `SyncService` still coalesces pulls independently from pushes, `RealtimeService` publishes subscription state only after awaited teardown and subscribe calls, its teardown omits the debounce task, `AuthService.signOut()` swallows remote sign-out errors, the pending activity cursor uses one global defaults key, and receipt upload failures do not increment `pushFailures`. Account-local cleanup is centralized through `AuthService.onSignedOut` in `TabApp`, so the departing user's scoped activity cursor can be removed there alongside the SwiftData wipe.

## 2026-07-18 20:43 BST — Test seams added first

Added Swift Testing specifications in `TabTests` for the extractable lifecycle seams: FIFO execution with no overlap in a serial async gate, generation-token invalidation of stale asynchronous work, and deterministic user-scoped activity cursor keys. Per the task constraint, these iOS target tests are not run with `xcodebuild`; implementation follows against these initially unresolved interfaces, while the allowed executable self-check remains `swift test` for `Packages/TabCore`.

## 2026-07-18 20:44 BST — Lifecycle fixes implemented

Added a main-actor FIFO task gate and routed both `pullAll()` and `pushPending()` through it while retaining the existing one-trailing-pull coalescing state. Added a reusable generation token to realtime subscription attempts; teardown now clears published state before awaiting, cancels stream and debounce tasks, and removes the SDK channel. Each attempt uses a distinct topic so an older same-trip attempt cannot accidentally remove the newest channel object.

Changed explicit sign-out to log remote failure and invoke Supabase Swift's local-scope sign-out fallback before completing app-local teardown. Verified this contract against the locally resolved Supabase Swift `v2.46.0` source after official documentation was unreachable from the sandbox; that SDK clears its session manager before the local-scope network request. Scoped the pending activity cursor defaults key by normalized user UUID and passed the departing user ID through the existing sign-out cleanup hook so its key is removed with the SwiftData wipe. Receipt upload failures now contribute to the existing `pushFailures` error phase while leaving pending receipt files in place for retry.

## 2026-07-18 20:45 BST — Static review

Confirmed the old global activity cursor key is no longer read or written, all sign-out hook call sites use the departing-user parameter, and all realtime teardown paths cancel and nil the debounce task. `git diff --check` and Swift parser checks pass. The standalone concurrency helper also type-checks under Swift 6 complete concurrency with its module cache under `/tmp`.

## 2026-07-18 20:46 BST — Validation

Ran `CLANG_MODULE_CACHE_PATH=/tmp/tab-ws2-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/tab-ws2-swiftpm-module-cache swift test --disable-sandbox` from `Packages/TabCore`. The build and all 155 Swift Testing tests across 11 suites passed. SwiftPM emitted only pre-existing cache-access and redundant-`#require` warnings. No `xcodebuild`, simulator, remote database, storage, auth, or realtime service operation was run.
