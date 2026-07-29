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
