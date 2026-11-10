# Project health audit

## Goal

Read the whole repository, fix what is plainly broken, stale or unused, and list everything that needs a decision.

## Log

### 2026-11-10: method

- Seven read-only Opus reviews, one per area: domain, data and sync, screens, shared UI and config, Supabase, docs and site, and a dead-code sweep of `mobile/`.
- Baseline before any change: `npm run typecheck`, `npm test` (428 tests), `prettier --check` and `supabase/tests/00_sql_assembly.sh` all passed.
- Each finding was checked against the code before it was fixed or listed. Nothing touched a database, and no SQL, migration, RLS, edge function or `config.toml` was edited.
- After the fixes: typecheck passes, 431 tests pass, prettier passes.

### 2026-11-10: fixed

Sync and local data (`mobile/src/data`):

- `selectors.ts` `unsyncedChanges` now lists waiting receipt photos, a renamed profile and mute changes. The sync status already counted them, so Settings said "1 waiting" while the review screen said "Everything is synced", and sign-out gave no warning before deleting a photo that had not uploaded.
- `sync.ts`: rows under a deleted trip are cleared. A new expense, payment or pending person under a deleted trip used to wait forever with no way to discard it. Unsent rows are removed and previously synced rows are acknowledged, the same rule the engine already applied to deleted rows.
- `sync.ts` `removeTripOps` and `actions.ts` `discardLocalChange` remove the trip's mute row with the trip, as `merge.ts` already did.
- `receipts.ts`: a waiting photo on a deleted expense is dropped instead of counting as pending forever.
- `realtime.ts`: a trip opened before its first push subscribes once the push lands.

Screens and shared UI:

- Trip menu hides People on non-group containers, where the server refuses every people change.
- Settle-up shows the same "isn't available any more" screen as the expense form when the trip or the edited payment is gone. It used to render blank, or quietly switch to recording a new payment. Both forms clear the Save button on that screen.
- Friend history shows category icons (`friends-presenter.ts` passed an empty category list) and groups days with a per-date UTC offset, like the trip timeline.
- Trip overview remembers the chosen currency by code, so a new currency arriving does not switch the page.
- Splitwise import shows the error when a second file fails to parse.
- Turnstile sheet starts clean each time it opens.
- Email sheet ignores a second return-key save while one is running.
- Invite redemption no longer locks for the session if reading the saved token throws.
- Amount entry stops at twelve whole digits, the limit of the server's `numeric(20, 8)` columns.

Removed because nothing used them: `clearLocalData`, `setPreference`, `addTripPerson`, `relativeDay`, `PaymentMode`, `splitTypes` in `models.ts`, unused legacy re-exports, six unused imports, an identity `SPLIT_LABEL` map, one unused style, the `expo-clipboard` dependency, the `lint` script (no ESLint is installed), two unreferenced site screenshots (680 KB), and `docs/processes/testflight-distribution.md` (the Swift-era runbook; the `testflight` skill is the procedure).

Docs corrected: `AGENTS.md` matches `CLAUDE.md` on when claims run, design folder table lists all seven folders, `README.md` test commands run as written, `CONTEXT.md` describes when the activity cursor moves and when a pending person is claimed, `supabase/sql/README.md` lists files 19 to 21, `supabase/tests/README.md` lists all sixteen files with current counts, the send-push README drops its out-of-date status section, `mobile/README.md` names the settlement screen, and the validation logs inside `domain/API.md` and `data/legacy/README.md` are gone (the legacy one moved to the 2026-10-18 working log).

### 2026-11-10: for review

Database, needs a migration plan:

1. Trip renames lose to any later expense. `touch_trip_last_activity` updates the trip on every expense or settlement write, and `set_sync_fields` restamps `updated_at`, so a rename made before that write is dropped as stale. The app then shows "This was deleted, or you no longer have access to it". (`supabase/sql/05_expenses.sql:85`, `00_extensions.sql:41`, client `sync.ts` `updateOne`.)
2. Account deletion leaves the email in `trips.member_signature` of shared non-group containers. Other members can read it, and the same email signing up again rejoins the old ledger. (`20_account_deletion.sql:54`, `19_rpc_non_group.sql:59`.)
3. `set_sync_fields` trusts a client `updated_at` with no upper bound. A phone with a clock in the future wins every later edit.
4. `purge_soft_deleted_records` hard-deletes tombstones that delete-wins depends on. It is not scheduled. Decide whether to drop it or keep it with a long grace period.
5. A direct REST update can set `expenses.last_edited_by` to any trip member.
6. `push_devices` accepts any text as a token, and its insert policy skips the "release from other accounts" step of `register_push_device`.
7. Missing indexes on paths every full sync runs: `activity_log(timestamp)` and `trip_people(email) where user_id is null`.
8. RLS policies call `is_trip_member()` per row on full-table pulls. Fine today, grows with the whole table.
9. `pgtap` is created in the production baseline. Two indexes duplicate the leading column of a unique index. Four indexes and `suggest_trip_people` are unused by the Expo app; check the Swift client before dropping.
10. Deny-path tests are missing for `categories`, `expenses` (direct REST), `settlements`, `trips` update, `profiles`, `activity_log`, and the receipt storage policies.

Safety and privacy, no migration needed:

11. `supabase/scripts/clear_receipts_storage.sh` empties the receipts bucket of any project ref it is given, production included, behind one self-declared env flag. Delete it or make it refuse anything but the local stack.
12. `docs/legal/app-store-privacy-labels.md` says the app has no Contacts permission. `app.config.ts` adds the `expo-contacts` plugin with a permission string, and Turnstile is not covered. Check what the app prompts for and update the App Store answers.
13. Signing out offline leaves the push token registered on the server, so the signed-out phone keeps receiving that account's pushes. (`push.ts:63` ignores the delete's error.)
14. `.mcp.json` points at the hosted Supabase MCP with no `read_only` flag.
15. `supabase/config.toml` allows the redirect `com.example.tab://auth-callback`; the app's scheme is `com.rithwikshetty.tab`. Also confirm in the production dashboard that email confirmation or code-only sign-in is on, since claims trust `auth.users.email`.

App behaviour:

16. `balance-engine.ts` `distributePairs`: with two payers and remainders that tie, the lowest-UUID payer gets every spare cent. A and B pay 50.00 each, split three ways, gives A owed 50.01 and B 49.99. The Swift app does the same, so fixing it changes what older clients show by a cent.
17. If the local database fails to open, the app sits on the splash screen forever. `session.tsx` only logs the error.
18. An expense that names a person the server refused to add waits forever with no error and no Discard. (`sync.ts` `peopleReady`.)
19. A storage refusal with no error code is treated as "offline", which blocks every later pull. `remote.ts` `toRemoteError` never reads the error's own `status`.
20. An invite link tapped while the app is in the background can be missed until the next foreground. (`(app)/_layout.tsx` and `join/[token].tsx` race on SecureStore.)
21. `auth-callback.tsx` ignores a failed code exchange and lands on sign-in with no message.
22. Your own avatar uses the name from auth metadata, so it keeps the old initial after you rename yourself until the next sign-in.
23. Removing or replacing a receipt never deletes the old object from Storage.
24. Session chunks in `lib/supabase.ts` are overwritten in place. A kill mid-write leaves invalid JSON and signs the user out.
25. `category-icon.tsx` comment says custom icons draw as emoji or text; the code draws the `tag` glyph.
26. Amount fields accept non-ASCII digits that the parser then rejects.
27. Performance on large trips: every `ack` is its own commit, presenters scan all payments and splits per expense, every commit invalidates every screen's memo, and the trip timeline and Activity render with `.map` in a ScrollView. Activity also runs a full pull on every tab focus.

Dead or duplicated code that needs a choice:

28. Domain modules used only by their own tests: `auth-helpers.ts`, `settlement-amount-draft.ts`, `expense-payment-ledger.ts`, most of `conflict-resolver.ts`, the CSV and text exporters, and about a dozen helpers. The app has its own versions of several (`inviteTokenFrom` regex versus the tested `inviteToken`, `data/merge.ts` `resolveConflict`, two email validators, two timestamp parsers). Pick one of each and delete the other.
29. About 27 Swift-style namespace objects (`BalanceEngine`, `MoneyFormatter`, and so on) have no code references. `CONTEXT.md`, the ADRs and SQL comments use those names, so they still work as search anchors.
30. `react-dom` is only needed for a web target. Seven theme tokens are unused while three of them are rebuilt inline. Several props on `ui/primitives.tsx` are never set by a caller.

Docs that need a decision:

31. `docs/specs/client-functional-spec.md` is the Swift-to-Expo parity checklist: 304 lines cite `Apps/` and `Packages/` paths that no longer exist, and it contradicts the app in places (camera, Settings entries). `CLAUDE.md` calls it the behaviour checklist. Rewrite against `mobile/src`, or relabel it.
32. `docs/legal/privacy-policy.html` has drifted from the live `site/privacy.html`: older effective date, no Turnstile disclosure. Keep one copy.
33. `.env.example` lists variables nothing reads and none of the `EXPO_PUBLIC_*` ones the app does.
34. `docs/app-store/launch-checklist.md` is the finished 1.3.0 checklist. `metadata.md` says "Equal or exact splits" and the screenshots show the Swift 1.0 app.
35. Swift-era reports and research under `docs/reports` and `docs/research` are unreferenced history.
36. `supabase/sql/README.md` says never rewrite the deployed baseline, but `00_sql_assembly.sh` fails unless the baseline equals the regenerated `sql/`, so every SQL edit rewrites it. `CONTEXT.md` still says the purge window is 30 days.
37. `site/.well-known/assetlinks.json` is missing, so Android invite links open in the browser. Already a release to-do in `mobile/README.md`.
38. `.gitignore` carries Swift-era rules. Left alone because one of them hides an old secrets file that may still exist in a local checkout.

### 2026-11-10: second pass, the review list worked through

The owner asked for the review list to be done end to end. Three background Opus agents ran alongside the main session: database migrations (local stack only), the functional spec rewrite, and dead-code removal. Each agent's output was read and rechecked before it was kept.

Numbers refer to the review list above.

Fixed in the app:

- 13: sign-out asks before leaving when the phone can't remove its push token (`push.ts` `unregisterPushDevice` returns whether the server was told; `settings.tsx` `doSignOut`).
- 16: `balance-engine.ts` `distributePairs` splits each debtor's share by what the creditors are still owed, so every creditor ends up with exactly their net.
- 17: a local store that won't open shows "Couldn't open your trips" with Try again and Sign out (`session.tsx` status `failed`, `app/_layout.tsx` `StoreFailed`). Sign out there keeps the data on the phone; there is no reset option yet.
- 18: an expense or payment naming a person the server refused gets an error and can be discarded (`sync.ts` `whenPeopleReady`).
- 19: `remote.ts` `toRemoteError` reads an error's own HTTP status, so a storage refusal is not classed as offline.
- 20: saving an invite notifies the signed-in layout, which redeems it at once (`invites.ts` `onPendingInvite`).
- 21: `auth-callback.tsx` reports a failed code exchange and stands down while the in-app Google browser flow is exchanging its own code.
- 22: `useMyName` gives every screen the profile name, so avatars follow a rename.
- 25: the category icon comment matches the code. Custom icon names fall back to the tag glyph.
- 26: amount fields keep ASCII digits only.
- 27, in part: presenters group payments and splits once per trip, activity timestamps are parsed once, and the Activity tab skips its pull when a sync finished in the last 30 seconds.
- 28 to 30: 733 lines removed from `mobile/src`. Namespace objects, test-only modules (`settlement-amount-draft`, `expense-payment-ledger`, most of `conflict-resolver`, CSV and text export, auth helpers apart from `inviteToken`), unused props and theme tokens are gone. The invite sheet uses the domain `inviteToken`. Meta keys have one definition in `schema.ts`. The email code length is read in `lib/config.ts`.
- Found while rewriting the spec and fixed: a blank column in a Splitwise header shifted every later amount to the wrong person; imported descriptions that were blank or over 200 characters were refused by the server; a failed trip create left the form stuck; the "settled" month used UTC; replacing a receipt offered only the library.

Database, written and tested locally, not applied to production:

- 1 and 3: `20261110055639_trip_activity_bump_and_clock_cap.sql`.
- 5: `20261110055709_expense_editor_guard.sql`.
- 2: `20261110055715_account_deletion_signature_scrub.sql`.
- 7: `20261110055720_sync_query_indexes.sql`.
- 10: `supabase/tests/16_rls_deny_paths.sql` and additions to `01`, `11`, `13`, plus `17_expense_editor_guard.sql`. 17 suites, 389 assertions pass on a copy of production's schema with the migrations applied and on a fresh reset.
- 11: `clear_receipts_storage.sh` deleted.
- 15: `config.toml` redirect uses the real scheme and `send-push` has `verify_jwt = false`.
- The plan, with pre-flight queries, backup, verification and rollback, is `docs/reports/2026-11-10-audit-migrations-rollout-plan.md`.

Docs:

- 31: `docs/specs/client-functional-spec.md` describes the Expo app, with evidence paths in `mobile/src` and `supabase/sql`.
- 32 to 35: deleted the duplicate privacy policy, `.env.example`, the 1.3.0 launch checklist and four Swift-era reports and research notes. `metadata.md` lists all four split types.
- 12: the privacy labels doc states that the app asks for Contacts access to read the picked contact, and notes Turnstile.
- 36: the Supabase READMEs describe the editing workflow as practised and the purge hazard.

Checked in the production dashboard, read-only, through Chrome: Confirm email is on, CAPTCHA is Turnstile, the only redirect URL is `com.rithwikshetty.tab://auth-callback`, Cron is not installed, and the newest migration is `20261019145418`. The Site URL is still `http://localhost:3000`. The project home showed "Restoration in progress" then "Restoration complete" on first load.

Verification:

- `npm run typecheck`, `prettier --check` and `00_sql_assembly.sh` pass. `npm test`: 398 pass. The count is lower than before because 37 tests covered only deleted code.
- Fresh iOS development build on the simulator against the local stack with the new migrations: sign-in, Trips, trip detail, overview currency switch, trip menu, record a payment (amount stops at twelve digits), new expense with validation, expense detail, Friends and friend history with category icons, Activity, Settings. A new expense synced, and a trip rename made after it reached the local database.

Left open:

- The four migrations need the owner's approval and a production apply. Until M1 is applied, a trip rename made before a later expense is still dropped.
- 4: `purge_soft_deleted_records` is kept, unscheduled, with the hazard documented.
- 6, 8, 9: push token format and policies, RLS policy rewrite for speed, pgTAP in production and unused indexes. Each needs a check against older Swift clients or has little value today.
- 14: `.mcp.json` has no `read_only` flag. Left as is because production applies have gone through that server.
- 23: a removed or deleted receipt's object stays in Storage. The client cannot delete it once the path is cleared, so this needs a server-side sweep.
- 24: session chunks are written in place. A kill mid-write signs the user out but loses no data. Changing the storage format risks signing everyone out on update.
- 27, rest: list virtualisation for the trip timeline and Activity, and batching acknowledgements after a large import.
- 37: `assetlinks.json` needs the Play signing key fingerprint.
- 38: `.gitignore` Swift-era rules.
- App Store Connect: privacy answers, description text and screenshots still describe the old app. The docs hold the corrected text.
- Supabase dashboard: Site URL, and whether the project had been paused.

### 2026-11-10: third pass, the open items closed and the database work applied

The owner asked for the open list to be finished and for everything to be merged and deployed.

Fixed in the app:

- 24: `lib/supabase.ts` keeps the session in one of two SecureStore slots. A write fills the other slot and moves the `<key>.at` pointer last, so a write cut short keeps the previous session. A session in the older layout is read as is and moved on the next write. Tests in `lib/supabase.test.ts` cover a cut-short write, the older layout and clean-up.
- 27: the trip timeline is a `FlatList` and Activity is a `SectionList`. Each row draws its own slice of the day's card (`Card` takes `first` and `last`), and rows are memoised by value (`sameValues`), so a store update re-renders only rows whose values changed.

Fixed on the server:

- 23: `supabase/sql/22_receipt_sweep.sql` and the `sweep-receipts` edge function. Once a day pg_cron asks the function to remove receipt objects that no live expense points at, where neither the object nor its expense has changed for 30 days. Test `18_receipt_sweep.sql`, 13 assertions.

Applied to production (`gaseuxsieddlksxtdliq`) with `supabase db query --linked --project-ref`, one transaction per migration with its drift guard and its history row. `docs/reports/2026-11-10-audit-migrations-rollout-plan.md` has the pre-flight results and the checks after each apply.

- Recorded versions: `20261110055639`, `20261110055709`, `20261110055715`, `20261110055720`, `20261110055757`. The migration files carry those versions.
- Pre-flight found no row stamped in the future and no container with a stale signature, so no data fix ran.
- The `receipts` bucket held 7 objects from May and June whose expense rows were gone. The first sweep, requested by hand, removed all 7.
- The Supabase MCP server was not authorised in this session, which is why the CLI was used.

Verification:

- `npm run typecheck` and `prettier --check` pass. `npm test`: 403 pass in 38 files.
- `00_sql_assembly.sh` passes. After a fresh `reset_local.sh`, all 18 pgTAP suites pass, 402 assertions.
- The sweep was run end to end on the local stack with real uploaded files, through the edge function directly and through `pg_net`.
- Simulator, iOS development build against the local stack: a trip with 403 expenses scrolls with each day drawn as one card, an expense opens from the list, Balances and Overview render under the same header, and an Activity feed of 400 rows scrolls and swipes inside its card. The build kept its session across the storage change, which is the older-layout read path.

Still open, with the reason:

- 37: `site/.well-known/assetlinks.json`. There is no Play listing yet, so there is no signing key to publish.
- 27, acknowledgements: each row is acknowledged in its own commit right after the server confirms it. That is what keeps a killed app from re-sending confirmed rows, so it stays.
- 4, 6, 8, 9, 14, 38: unchanged from the list above. Production has 120 expenses, so the RLS and index items buy nothing yet.
- App Store Connect text, screenshots and privacy answers, and the Supabase Site URL, are dashboard changes for the owner.
