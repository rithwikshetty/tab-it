# Sync data integrity fixes

## 2026-07-18 19:07 BST — Goal

Fix GitHub issues #13, #14, and #18 without disturbing unrelated work: paginate every destructive-reconcile pull, acknowledge only the exact write IDs serialized before each async push, and make the database trigger apply live-to-deleted updates unconditionally. Work test-first where the logic has a pure seam, regenerate the Supabase baseline, run the requested local-only validations, and leave logical commits with a clean worktree.

## 2026-07-18 19:10 BST — Initial inspection and current documentation

Read the repository instructions and domain context, confirmed the starting worktree was clean, and located the pull, reconcile, push, trigger, and existing LWW pgTAP coverage. The agreed unit-test seam is a generic closure-injected pagination helper in the app target. Current Supabase Swift documentation confirms the hosted 1,000-row default and recommends `range()` pagination; stable ordering will be applied before every range. The current Supabase changelog has no relevant breaking change that alters this approach. Per the task constraint, no remote database will be contacted.

## 2026-07-18 19:11 BST — Pagination TDD and pull conversion

Added Swift Testing coverage first for multi-page assembly, exact-boundary pagination (including the required trailing empty request), an empty result, and a later-page error. The initial targeted Xcode test attempt could not reach compilation because this managed workspace blocks CoreSimulator and writes to the default Xcode/SwiftPM caches. Implemented `fetchAllPages`, which returns only after a short page and rethrows any page error without returning partial rows. Converted every table pull to use stable ordering plus inclusive ranges: `id` for ID-keyed rows, `(expense_id, trip_person_id)` for payment/split ledgers, and the complete composite keys for mute preferences. Activity remains time-windowed but is now fully paginated within that window. A second build-for-testing attempt with writable temporary caches was still stopped during package resolution because SwiftPM attempted a nested `sandbox-exec`, which this managed sandbox forbids; final validation will retry the exact requested command.

## 2026-07-18 19:13 BST — Git boundary limitation

Attempted the requested logical commit for issue #13 after `git diff --check` passed. Git could not create the worktree `index.lock` because the worktree's Git directory resolves to `/Users/rithwikshetty/Downloads/dev/tab/.git/worktrees/wt-ws1`, outside the writable sandbox. Source files remain writable and intact, so implementation continues; commit creation and a clean Git status may remain impossible under the current permission profile.

## 2026-07-18 19:16 BST — Async push acknowledgement sweep

Swept every `pushedWriteID` assignment in `SyncService`. Profile, trip creation/update, settlement create/delete, expense delete, the transactional expense/payment/split RPC, and mute insert now capture the acknowledged local write ID before their network suspension and assign only that captured version afterward. The expense RPC snapshots the exact payment and split entity/version pairs used to build its arrays, so relationship edits during the await also remain dirty. The unmute path retains its identity check because a re-toggle must prevent deletion of the local tombstone. Swift parser validation and `git diff --check` pass for the edited Swift sources.

## 2026-07-18 19:19 BST — Database delete-wins trigger

Extended the existing `11_sync_lww.sql` pgTAP suite from 19 to 20 assertions before changing the trigger. The new assertion sends a tombstone whose `updated_at` is older than the current live row and requires the delete to apply; the existing two resurrection assertions remain immediately afterward and still require a newer live write to be ignored. Updated `set_sync_fields()` so live-live writes alone use ordinary `updated_at` LWW, both-deleted writes retain `deleted_at` LWW, live-to-deleted writes bypass timestamp rejection, and deleted-to-live writes remain blocked. Updated the function comment, regenerated the baseline, and ran the permitted static assembly check successfully. No remote database or pgTAP execution was attempted.

## 2026-07-18 19:21 BST — Final validation and compiler fallbacks

Ran all three requested commands. `bash supabase/tests/00_sql_assembly.sh` passed exactly. The exact `swift test` invocation was blocked while compiling the package manifest because the managed sandbox denies writes to `~/.cache/clang`; rerunning the same 154-test suite with writable temporary caches, `--disable-sandbox`, and a temporary scratch path passed all 154 tests. The exact iPhone 17 Pro `xcodebuild test` invocation was blocked before build/test execution because CoreSimulatorService is unavailable and Xcode cannot write its package checkout/cache directories under this permission profile.

Used compiler-level fallbacks to distinguish infrastructure failures from source failures. A temporary SwiftPM harness compiled and ran the four new pagination tests; it initially exposed a missing explicit closure return in the exact-boundary test, which was fixed, after which all four passed. A full iPhone Simulator SDK typecheck of every app source under Swift 6 strict concurrency exposed and then verified fixes for explicit returns in the payment/split payload maps. Finally, emitted a testable app module and typechecked the entire `TabTests` source set, including the new suite; it passed. Regenerated the ignored Xcode project and verified both new Swift files are members of their intended targets. Temporary validation harness files were removed.

## 2026-07-18 19:22 BST — Final repository state limitation

`git diff --check` passes and all intended source changes are present. Repeated logical commit attempts remain blocked because Git cannot write the external worktree index lock. Consequently this sandbox cannot satisfy the requested committed/clean repository state; the only remaining changes reported by `git status --short` are the intended implementation, tests, generated baseline, and this working log.
