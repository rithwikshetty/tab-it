# Android repository planning

## 2026-07-29 08:45 BST — Goal

Research whether tab should reorganize its existing repository before beginning a native Android client, and define a production-safe phased approach. This is architecture and planning work only: do not connect to, query, or modify the live Supabase project or any other database.

## 2026-07-29 08:45 BST — Initial repository finding

The repository already has the useful top-level separation for a mobile monorepo: the iOS client is under `Apps/Tab`, pure Swift logic is under `Packages/TabCore`, and backend, design, site, and documentation sources are independent top-level areas. The working hypothesis is therefore to avoid moving existing files and add the Android build as a sibling only when implementation begins.

## 2026-07-29 08:45 BST — Research direction

Primary-source research is focusing on Android and Gradle modularization guidance, official reference application structures, Kotlin Multiplatform tradeoffs, and Supabase environment isolation. The Supabase production project remains explicitly out of scope; future Android integration should use mock/local data first and a separate development environment before any production connection is considered.

## 2026-07-29 08:46 BST — Production-safety finding

The repository guidance is inconsistent with the user's confirmed production state. `AGENTS.md` still says there are no real users and permits destructive schema recreation, while `supabase/scripts/recreate_db.sh` loads `.env.local` and ultimately defaults to destructive SQL against the currently linked remote database. No Supabase CLI command, MCP operation, database connection, or query was run during this review. Correcting the repository instructions and making destructive tooling fail closed around remote targets should precede Android implementation; these would be repository safeguards, not database changes.

## 2026-07-29 08:48 BST — Research conclusion

Primary-source research supports keeping one Git repository with independent iOS and Android build roots. The existing iOS tree should remain in place; `Apps/TabAndroid` should be introduced only when the first compiling Android skeleton is built. Android should start with only an application module and a pure Kotlin domain module, using packages for local data, remote data, sync, and UI until real dependency pressure justifies additional Gradle modules. Phase 0 should define the architecture decision, parity matrix, production-safety boundary, and read-only backend compatibility inventory before any Android implementation.

## 2026-07-29 08:48 BST — Artifact and validation

Saved the cited research note at `docs/research/2026-07-29-android-repository-architecture.md`. `git diff --check` completed successfully. The only worktree changes from this planning task are the research note and this append-only working log; no application, backend, schema, configuration, or database state was changed.

## 2026-07-29 09:01 BST — Production guardrails implemented

GitHub issue #33 now tracks the Android foundation. Removed `supabase/scripts/recreate_db.sh` and its `destructive_teardown.sql` input. Updated `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, Supabase source documentation, and the historical launch/ADR notes to reflect that production contains real users. The new standing rules make production read-only by default, prohibit reset/recreate/drop/truncate/reseed/bulk-delete operations, require forward-only compatibility-preserving migrations, establish GitHub Issues as the main tracker, and require concise living HTML reports under `docs/reports/` for plans and phase outcomes.

## 2026-07-29 09:01 BST — Linked-target fallbacks removed

Changed the pgTAP runner to use `--local` only and stopped it from loading `.env.local`. Changed receipt-storage cleanup to refuse execution without `TAB_CONFIRM_NONPRODUCTION_STORAGE=1`, an explicit project ref, and an explicit service-role key; removed its linked-project fallback. No Supabase CLI, MCP, SQL, Auth, Storage, Realtime, Edge Function, or database operation was run.

## 2026-07-29 09:01 BST — Living HTML plan created

Created `docs/reports/2026-07-29-android-delivery-plan.html`, using the locked sage palette and a concise single-page structure: current decision, repository shape, phased roadmap, production firewall, and next review gate. The report links GitHub issue #33 and the supporting primary-source research note. Initial HTML validation found three semantic issues (DOCTYPE casing and two labelled generic groups); those were corrected before final verification.

## 2026-07-29 09:02 BST — Final verification and tracker update

`html-validate` passes for the report. Both modified shell scripts pass `bash -n`. The receipt cleanup helper was exercised with non-production confirmation absent and correctly refused before network access with exit status 1. `bash supabase/tests/00_sql_assembly.sh` passes and reports the baseline unchanged. Searches confirm the deleted recreate/teardown paths and stale “no real users” language are absent from active repository guidance; the only remaining `--linked` text is a comment explicitly documenting that the local-only test runner does not use it. `git diff --check` passes. GitHub issue #33 has a checked scope and milestone/completion comments and remains open for user review.

## 2026-07-29 13:21 BST — Android stack recommendation reverified

Rechecked the proposed implementation stack against current first-party Android guidance. Google remains Kotlin-first and recommends Kotlin for new Android apps, strongly recommends Jetpack Compose for new native interfaces, and documents Gradle with the Android Gradle Plugin as the normal Android build path. The research note now records this evidence and clarifies that Flutter, React Native, and Kotlin Multiplatform are valid alternatives but are not the default native Android stack. For tab, a separate Kotlin/Compose client remains the conservative choice because it preserves the existing production iOS app.

The supporting Android pieces also align with first-party guidance: Room for structured offline storage, coroutines and Flow between layers, and WorkManager for persistent synchronization work. Supabase documents an Android Kotlin integration, but its Kotlin client is community-maintained rather than an official Supabase SDK; that dependency should therefore stay behind a small adapter and be evaluated with mock or isolated non-production tests during a later phase. No production system, database, credential, GitHub issue, or external service was accessed or changed.

## 2026-07-29 13:24 BST — Initiative expanded

The user expanded the initiative from planning and Phase 1 to completing every Android phase locally. The execution boundary remains strict: production Supabase is read-only unless the user explicitly authorizes a specific production operation.

## 2026-07-29 13:28 BST — Local toolchain and link-state audit

Docker and Supabase CLI are available, but Java, the Android SDK, Gradle, emulator tooling, and Android Studio are not installed. The repository's ignored Supabase state still contained a previous hosted-project link, and the database test guide still documented a linked remote query command. The stale ignored link state was recoverably archived outside the repository before any local database operation.

## 2026-07-29 13:33 BST — Local Supabase safety layer

Added a checked-in `tab-local` Supabase configuration, fictional development seed data, local-only start/reset/verification guards, and changed database tests and documentation to require explicit local execution. A negative guard test correctly refused execution when a remote Supabase environment variable was present.

## 2026-07-29 13:38 BST — First local stack validation

Started the local Supabase stack. The immutable baseline migration and fictional seed applied successfully, and verification found project-scoped `tab-local` containers and local development URLs. The CLI also confirmed that its development ports bind to all host interfaces, so the documentation accurately requires a trusted development machine and network rather than claiming loopback-only exposure.

## 2026-07-29 13:42 BST — Reset-network finding and pivot

The first reset exposed an incompatibility between a custom Docker network and Supabase CLI's reset workflow: the recreated database container was unreachable by Storage. Stopped only the `tab-local` stack, preserved its local volumes, and removed the custom-network override from the start script. The supported project-scoped default network will be validated with a clean start, reset, seed, and full database test run.

## 2026-07-29 13:47 BST — Fresh-install privilege gap isolated

The supported default network passed reset, but the first complete pgTAP run exposed a separate clean-install contract gap: the immutable baseline defines RLS policies without recreating the authenticated table privileges relied on by the application. The test runner also needed to use the exact local Postgres container because Supabase CLI 2.109 cannot execute the suites' multi-statement files as one prepared query. Added an explicitly local-only ACL overlay and opened GitHub issue #34 for a future, separately approved forward migration; neither the baseline nor production was changed.

## 2026-07-29 13:50 BST — Local backend phase verified

A second clean local reset successfully applied the baseline, local ACL overlay, and fictional seed. All 15 pgTAP suites passed through the guarded `supabase_db_tab-local` container. The seed contains one trip, four people, three expenses, and one settlement. A negative test confirmed that a remote project environment variable makes the guard refuse execution, and unrelated Docker services remained running. Added the verification result to GitHub issue #33 and linked the production-safe follow-up in #34.

## 2026-07-29 13:54 BST — Local privilege setup simplified

The generated Supabase configuration documents a supported legacy compatibility switch for automatically exposing newly created tables to API roles. Replaced the hand-written local ACL overlay with `api.auto_expose_new_tables = true`, which more accurately recreates the existing project behavior. The switch is deprecated, so issue #34 still tracks explicit grants through a future approved forward migration.

## 2026-07-29 14:03 BST — Android toolchain selected and installed

Reverified the current stable compatibility chain from first-party Android and Kotlin sources. Selected JDK 17.0.20, AGP 9.3.0, Gradle 9.5.0, Kotlin 2.4.10, Compose BOM 2026.06.00, compile SDK 37, and target SDK 36. Installed JDK 17 plus Google's command-line SDK tools, platform tools, emulator 36.6.11, build tools 36.0.0, API 36 and 37 platforms, and the API 36 Google APIs ARM64 image.

## 2026-07-29 14:10 BST — Emulator verified

Created the `Tab_API_36` Pixel 7 virtual device and booted it headlessly. ADB reported a healthy ARM64 emulator running Android 16 / API 36. This gives the project a repeatable phone test target without requiring a physical Android device.

## 2026-07-29 14:18 BST — Android skeleton implemented

Opened GitHub issue #35 and created `Apps/TabAndroid` as an independent Gradle build. The initial graph contains only the Compose application and pure JVM `:core:domain` module. Added a checksum-pinned Gradle 9.5 wrapper, dependency locking, strict Kotlin warnings, debug-only local backend configuration, a release build with no backend URL, locked sage theme tokens, JVM tests, and a Compose emulator test.

## 2026-07-29 14:24 BST — Phase 1 clean verification

A clean build passed domain and app unit tests, Android lint, debug assembly, R8-minified release assembly, and the Compose instrumentation test on `Tab_API_36`. Installed and cold-launched the debug APK; ADB confirmed `MainActivity` resumed and the process stayed healthy. Visual inspection confirmed the foundation screen renders correctly with the sage palette. APK inspection found the expected `10.0.2.2:54321` URL only in debug and no local or hosted backend URL in release.

## 2026-07-29 14:29 BST — Complete domain surface mapped

Opened GitHub issue #36 for cross-platform behaviour parity. Mapped every public pure-logic area in Swift `TabCore`: exact money and currency precision, equal/exact/share/percentage splits, payer allocation, multi-payer balances, settlements, debt simplification, conflict resolution, trip state, trip analytics, cross-container friend balances, and Splitwise CSV import. The Android port stays in the pure JVM `:core:domain` module and has no Android, database, network, or production dependency.

## 2026-07-29 14:39 BST — Kotlin domain port and shared contract

Implemented the complete mapped rule set using `BigDecimal`, `BigInteger`, deterministic UUID ordering, currency minor units, soft-delete filtering, delete-wins conflict handling, and integer-minor-unit Splitwise reconstruction. Added `contracts/domain/parity-v1.json` as a platform-neutral contract and test adapters on both Swift and Kotlin. The fixture covers currency-specific equal-split remainders, multi-payer balance distribution, and trip-state boundaries.

## 2026-07-29 14:43 BST — Parity harness corrections

The first combined run exposed two harness details rather than product-rule differences: test working directories differed between SwiftPM and Gradle, and Kotlin `BigDecimal.equals` includes display scale while Swift `Decimal` numerical equality does not. The fixture lookup now discovers the repository root safely and balance assertions normalize decimal scale only for comparison. Direct Kotlin tests were added for all ported rule families, malformed import rows, deleted records, settlement direction, typed validation errors, multi-currency partitioning, and identity collapse.

## 2026-07-29 14:46 BST — Phase 2 clean verification

Swift `TabCore` passed all 158 tests across 12 suites, including the shared parity fixture. Android passed 22 pure-domain tests plus application unit tests, lint, debug assembly, and the minified release assembly in a clean 106-task run. The release build remains backend-unconfigured. No database, Supabase API, hosted service, or production credential was accessed during this phase.

## 2026-07-29 14:49 BST — Room foundation selected

Opened GitHub issue #37 for the local-first persistence phase. Current Android guidance still lists Room 2.8.4 as stable while Room 3 is a release candidate, so the Android-only `:core:data` module uses stable Room 2.8.4 with KSP 2.3.9. The module boundary keeps Android persistence out of the pure Kotlin domain and keeps future Supabase transport behind repositories.

## 2026-07-29 14:56 BST — Local schema and transaction boundary implemented

Added the versioned Room schema for profiles, trips, trip people, categories, expenses, payment and split ledgers, settlements, activity, mute preferences, receipt drafts, and the synchronization outbox. UUIDs and timestamps are stored as stable strings; exact decimal values are stored as plain decimal text. Mutable synced rows carry updated, deleted, write-ID, and dirty metadata. Expense, payment, split, receipt-draft, and outbox writes execute in one Room transaction.

## 2026-07-29 15:02 BST — Offline repositories and debug seed

Added Flow-based repositories that read active trips and expenses from Room, validate ledger totals before writes, preserve soft-deleted rows, and order eligible outbox work by its database sequence. Debug initialization idempotently creates one fictional user, trip, friend, category, and expense without queueing remote work; release initialization is deliberately empty.

## 2026-07-29 15:08 BST — Phase 3 emulator verification

Nine Room instrumentation tests passed on the API 36 emulator. They cover exported schema creation, exact decimal round-tripping, ledger/receipt/outbox atomicity, foreign-key rollback, soft deletion, retry scheduling, Flow observation, debug-seed idempotency, settlements, activity, and mute preferences. Android data lint and the R8-minified release build passed. A cold debug launch created `tab.db` in the application sandbox. Release declares no Internet permission and contains no local or hosted Supabase URL; production remained untouched.

## 2026-07-29 15:12 BST — Local authentication and sync issue opened

Opened GitHub issue #38 with the local-only authentication, snapshot, outbox, conflict, retry, realtime, emulator, and release-safety acceptance criteria. The phase uses the current Supabase Kotlin BOM behind a repository-owned `RemoteGateway`; release configuration remains empty.

## 2026-07-29 15:18 BST — Fictional Auth seed and ignored debug configuration

Extended the disposable seed with confirmed email identities and bcrypt passwords for the three fictional local users. A guarded script now writes only the local publishable key to ignored Android `local.properties`; it never reads a hosted target or writes a secret or service-role key. A second script configures ADB reverse only for exactly one emulator and refuses physical devices.

## 2026-07-29 15:29 BST — Local sync boundary implemented

Added `:core:sync` with typed Auth and PostgREST transport, full RLS-filtered snapshot pulls, transactional snapshot application, ordered expense outbox delivery through the existing atomic RPC, exponential retry scheduling, last-write-wins and delete-wins merging, and current-trip realtime subscriptions. Remote rows hydrate Room in foreign-key order, while dirty offline rows survive older remote snapshots.

## 2026-07-29 15:37 BST — Realtime collection ordering corrected

The first realtime integration test established the websocket but timed out because channel flows were collected only after subscription. Changed the coordinator to start all four filtered collectors before subscribing. The selected-trip insert then emitted successfully on the emulator.

## 2026-07-29 15:45 BST — Phase 4 verified and local data restored

Android passed all unit tests, lint, debug assembly, R8-minified release assembly, nine data instrumentation tests, six synchronization instrumentation tests, and the Compose smoke test on the API 36 emulator. The sync tests cover real fictional sign-in, full pull and Room hydration, confirmed outbox push, offline retry retention, dirty-local conflict protection, remote delete-wins, and realtime delivery. APK inspection found no backend endpoint or key in release. A transitive Internet permission was found and explicitly removed from release; the rebuilt release declares no Internet permission. All 15 pgTAP suites passed, then the disposable stack was reset back to its three seeded expenses. Production was not accessed.

## 2026-07-29 15:50 BST — Android app shell and trip issue started

Opened GitHub issue #39 and checked current Android architecture guidance before replacing the foundation screen. The app now follows a single-activity Compose structure with Navigation Compose, repository-backed Room flows, a lifecycle-aware screen state holder, and manual constructor injection through one application container. The four iOS-aligned destinations are Friends, Trips, Activity, and Settings; unfinished destinations remain explicit placeholders rather than fake data.

## 2026-07-29 15:57 BST — Local session and trip flows implemented

Added persisted local Supabase session restoration, fictional email/password sign-in, guarded sign-out, and Room-first trip create, rename, and archive. New trips create their creator membership and an ordered outbox item in one transaction. Sync uses the existing `create_trip_with_self` RPC for first delivery and compatibility-preserving table updates afterward. Sign-out refuses to discard unsynced work, performs a successful sync first, then clears the account-local database to prevent cross-account data exposure.

## 2026-07-29 16:04 BST — App shell verified on emulator

The first device run exposed only assertion and realtime timing issues in the tests, not product failures: a raw trip observer intentionally includes tombstones, duplicate visible “Trips” labels made a single-node assertion ambiguous, and the realtime case passed when rerun outside the initially failing aggregate run. Corrected the assertions to distinguish active-list behavior from raw tombstone access. Ten Room tests, seven sync tests, and the Compose sign-in/navigation test then passed separately on the API 36 emulator. The local integration test verified create, rename, and archive against Docker only.

## 2026-07-29 16:12 BST — Phase 5 lifecycle coverage completed

Completed the issue's remaining shell requirements: pull-to-refresh, a navigation rail at tablet widths, selected-trip realtime that starts and stops with the destination, keyboard submit actions, session survival across Activity recreation, and a sign-out confirmation flow. Added an integration case for archiving a never-synced trip so the create and delete outbox entries cannot strand each other.

## 2026-07-29 16:18 BST — Resource leaks and sign-out threading corrected

The expanded sync suite made realtime intermittently time out because each test closed its session but not the Supabase client's HTTP and websocket resources. Added an explicit close boundary and test teardown; all eight sync device tests then passed together. The sign-out UI test also caught `RoomDatabase.clearAllTables()` running on the main thread. Moved account-local cleanup to the IO dispatcher. The full sign-in, Activity recreation, navigation, guarded sign-out, and signed-out state test passed afterward.

## 2026-07-29 16:22 BST — Phase 5 release checks passed

Android unit tests, lint, debug assembly, and the R8-minified release build passed in a 277-task run. The release artifact remains backend-unconfigured and networkless. The disposable Supabase database was reset to the fictional baseline after integration testing; no production service was accessed.

## 2026-07-29 16:27 BST — Phase 6 expense and membership slice implemented

Opened GitHub issue #40 and connected the trip detail screen to Room flows for active people, categories, and expense ledgers. Added trip expense, overview, and people surfaces; typed navigation for expense create, detail, and edit; local-first save and soft delete; and online-only add/remove membership operations through the existing local RPCs. The form supports exact decimal amount and currency, category, date, payment method, multiple payers, equal or exact participants, deterministic validation, and accessible live error announcements.

## 2026-07-29 16:27 BST — Device tests found and corrected lifecycle defaults

The full emulator flow caught two real edge cases before completion. Disposing one nested trip destination could clear selected-trip state after the next destination had set it, so selected-trip lifetime is now owned by the top-level destination transition rather than competing disposal callbacks. A new expense could also reach validation before its current-member payer default was populated; save now has an explicit deterministic default payer and participant fallback while still preserving deliberate multi-payer entries.

## 2026-07-29 16:27 BST — Local integration coverage expanded

Room tests now cover repository-level member, category, and individual expense flows. Supabase integration verifies member add and remove against the disposable local RPCs. Compose tests cover validation and exact-decimal expense construction, while an application-level test signs in, opens the seeded trip, creates an expense, returns to the list, opens its detail, and verifies payer and split ledgers. The pre-existing Realtime case timed out when embedded in the first aggregate run but passed in isolation; its test driver now retries a bounded local change while one subscribed collector waits, and the complete nine-test sync suite passes together.

## 2026-07-29 16:35 BST — Phase 6 clean verification

All Android JVM tests, debug lint, debug assembly, and the R8-minified release assembly passed in a 279-task run. Eleven Room tests, nine synchronization tests, and three Compose/application tests passed on the API 36 emulator. The release manifest has no Internet permission, and artifact inspection confirmed that neither a configured backend URL nor the local publishable key is present. The living HTML report passes semantic validation. The disposable local database was reset to its fictional seed after testing; production was not accessed.

## 2026-07-29 16:41 BST — Balances, repayments and Friends implemented

Opened GitHub issue #41 and added a Room-first settlement repository plus outbox delivery through the existing settlements table. Trip detail now derives mirrored per-currency balances with `BalanceEngine`, produces repayment suggestions with `DebtSimplifier`, and supports settlement create, detail, edit and soft delete. Friends aggregates the signed-in user's position across every active trip and hidden non-group container, retains pending and settled people, provides per-source detail, and routes each source into the same repayment form.

The existing `resolve_or_create_non_group_container` contract was reusable without schema work. Added a people-first flow that selects known people or normalized email invitees, asks the local RPC to resolve the exact participant set, pulls the server-managed container into Room, and opens the standard expense editor. Android never creates or pushes hidden container rows directly.

## 2026-07-29 16:48 BST — Phase 7 test failures corrected

The first local settlement integration assertion compared Postgres numeric display text instead of numeric value; it now compares `BigDecimal` values and the round trip passes. The first application repayment test expected lazy settlement-history content to be composed off-screen, then assumed the trip detail would remember the Balances chip after returning from a nested editor. The product correctly returned to the default Expenses section, so the test now waits for the enabled save action, verifies the return, reopens Balances, and checks the derived content. These corrections preserve the intended UI rather than adding state solely for a test.

A guarded local reset restored the fictional baseline. Its first emulator-forwarding attempt stopped safely because Android platform tools were not on that shell's path; rerunning with the documented SDK path established only the `localhost:54321` reverse mapping.

## 2026-07-29 16:55 BST — Phase 7 clean verification

All 15 pgTAP suites passed against `tab-local`. Android JVM tests, lint, debug assembly, and the R8-minified release assembly passed in a 277-task run. Twelve Room tests, eleven synchronization tests, and six Compose/application tests then passed together on the API 36 emulator. Coverage includes exact settlement persistence and deletion, settlement outbox round trips, server-managed non-group resolution plus expense sync, friend aggregation and source direction, repayment form behavior, application-level repayment navigation, and the Friends-to-expense flow.

The release manifest still has no Internet permission. Artifact inspection confirmed that the local publishable key, local backend URL, and hosted Supabase URL are absent from the release DEX. Production was not accessed.

## 2026-07-29 17:05 BST — Activity, mute and invitation slice verified

Opened GitHub issue #42 for the remaining product surfaces. Added a Room-backed Activity feed with deterministic unread rules, trip navigation and a durable local read cursor acknowledged by the existing `mark_activity_seen` RPC. Per-trip mute is local-first: each toggle updates Room and the ordered outbox before the existing `trip_mute_prefs` table is changed. Invite links use the deployed member-only RPCs for create, revoke and join; Android shares the same `https://tab-it.app/join/<token>` contract as iOS.

An initial integration run correctly exposed that authenticated clients have no direct `profiles` table privilege. Removed that attempted read rather than weakening RLS or changing the live schema contract. The local cursor survives normal pulls because snapshot application preserves it; the server RPC still advances notification state. All JVM tests, lint and debug assembly passed. Thirteen Room tests, twelve local Supabase tests and six Compose/application tests passed on the API 36 emulator. The local Supabase suite exercised mute/unmute, activity acknowledgement and invite create/join/revoke without production access.
