# Current Work Review

## 2026-07-01 21:39 BST

Goal: Review all current staged and unstaged changes, fix confirmed issues directly, check for a clear Linear connection, and run focused validation without staging or committing.

## 2026-07-01 21:41 BST

Reviewed the Supabase changes against the current privilege pattern. The new `public.sync_profile_name_to_trip_people()` trigger function is `SECURITY DEFINER` in `public`, but it was not added to the trigger-only function revoke list in `supabase/sql/17_privileges.sql`; patching that and regenerating the baseline.

## 2026-07-01 21:43 BST

Validation found that the app unit-test target fails to compile before running tests because `SplitwiseImporterTests` calls helpers on `@MainActor` app types from a nonisolated Swift Testing suite. The failure is outside the shares/name-sync diff, but it blocks the repo validation gate; applying the same `@MainActor` suite annotation pattern used by nearby app tests.

## 2026-07-01 21:45 BST

Validation passed after fixes: `git diff --check`, `bash supabase/tests/00_sql_assembly.sh`, `swift test` in `Packages/TabCore` (146 tests), XcodeBuildMCP `TabTests` on the booted iPhone 17 Pro simulator with mock auth (80 tests), and the two targeted new `PaidByFlowUITests` shares/percentage round-trip UI tests. No staged changes. No clear Linear issue ID was found in the branch name (`main`), recent commits, or current working logs, so Linear was skipped.
