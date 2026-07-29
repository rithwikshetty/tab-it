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
