# 2026-07-18 — Full-system audit (bugs + incomplete work)

## Goal

Repo-wide audit ahead of the 1.3.0 (16) release: find real bugs and unfinished work across the iOS app, TabCore, the Supabase schema/functions, and the site. Method: 7 parallel subsystem reviewers + test runs, every finding adversarially verified, plus an independent Codex pass over the sync layer and TabCore as a second opinion. Read-only — no fixes applied in this session.

## 2026-07-18 — Test baseline

- TabCore `swift test`: 154 tests, 11 suites, all pass.
- App `xcodebuild test` (TabTests, iPhone 17 Pro sim): 96 tests, 19 suites, all pass.
- `supabase/tests/00_sql_assembly.sh`: pass (baseline in sync with `supabase/sql/`).
- Remote pgTAP suites intentionally NOT run (prod DB has real data), but static review found suite 08 stale (below).

## 2026-07-18 — Confirmed findings (ranked)

### High

1. **Unpaginated pulls + reconcile hard-delete = local data corruption above the server row cap.** `SyncService.swift` pulls every table with bare `.select().execute()` (no `.order`/`.limit`/`.range`; e.g. pullExpenses ~L523, pullExpenseSplits ~L553) and `reconcileLocalRows` (~L660–753) deletes any pushed local row absent from the returned set. Supabase/PostgREST silently truncates at the default 1000-row cap, so once visible `expense_splits` (fastest-growing) exceed 1000, valid local rows are deleted and churn on every pull; balances go wrong. Independently found by both the workflow audit and Codex.
2. **Stale `writeID` acknowledged after await — edits/deletes made during an in-flight push are marked pushed and never sent.** Every push path does `try await …execute()` then `entity.pushedWriteID = entity.writeID`, reading `writeID` after the suspension point (trips ~L889, settlements ~L911, expense deletes ~L1003, create-expense RPC ~L1060, profile ~L818). A user edit or soft delete landing mid-request gets its new writeID marked clean; the newer write (including a tombstone) is silently dropped until a later unrelated edit re-dirties the row.

### Medium

3. **`pushPending` and `pullAll` are not mutually exclusive** — a pull snapshot taken before a concurrent push completes lets `reconcileLocalRows` delete the just-pushed row locally (self-heals next pull, but the expense visibly vanishes and balances flicker). `SyncService.swift:761` area.
4. **Concurrent `subscribe()` leaks a realtime channel** and keeps realtime + pull loops live on a trip the user left (fast trip switching passes the early-out before state is assigned). `RealtimeService.swift:28–63`.
5. **Currency switch leaves an exact multi-payer ledger at old precision** — fractional minor units can be saved; `canSave` precision check covers total only, not per-payment entries. `ExpenseEntryView.swift:476` area.
6. **DB delete-wins is one-directional.** `set_sync_fields()` (`supabase/sql/00_extensions.sql`) blocks resurrection of tombstones but routes live→delete through plain LWW, so a delete with an older `updated_at` than a concurrent edit is silently dropped — diverges from TabCore `ConflictResolver` rule 1 (a lone deleted side wins unconditionally).
7. **`send-push` treats APNs `BadDeviceToken` as a dead token and hard-deletes `push_devices` rows** — one APNS_ENV misconfiguration (defaults to `sandbox` in `apns.ts:9`) silently unregisters every real device. `supabase/functions/send-push/index.ts:141`.
8. **pgTAP suite 08 is stale and fails** — asserts the old zero-arg `mark_activity_seen` signature and pre-`joined_at` unread counts; masks regressions in the notification path. `supabase/tests/08_activity_notifications.sql`.
9. **Sign-out swallows Supabase sign-out failure** (`try? await client.auth.signOut()` in `AuthService.swift:226`) then wipes local state; token may stay unrevoked / session may resurface on restart. (Codex finding.)

### Low

10. Pull debounce task not cancelled on unsubscribe — a full pull fires ~400ms after leaving a trip. `RealtimeService.swift:87`.
11. Activity read-cursor pending key (`sync.pendingActivitySeenAt`) is global UserDefaults, survives sign-out, and can advance the next signed-in user's read cursor. `SyncService.swift:1105`.
12. Receipt upload failures swallowed (no `pushFailures` increment) while the expense already carries a `receipt_storage_path` other devices 404 on. `SyncService.swift:948–963`.
13. Expense-date display shifts a day forward in zones east of UTC+12 (noon-UTC anchor; display-only). `ExpenseDates.swift:10`.
14. Settle-up currency/pair change clobbers a user-typed partial amount with the full simplified debt. `SettleUpFormView.swift:139`.
15. Delete dialogs promise "You can recover it for 30 days" but no restore UI exists anywhere. `TripListView.swift:87`, `ExpenseDetailView.swift:76`, `SettlementDetailView.swift:64`.
16. `add_trip_person_by_email` DO UPDATE lacks the `user_id is null` guard its sibling RPCs have — any member can rename a claimed member and clear their `removed_at`. `supabase/sql/15_rpc_trip_people.sql:56`.
17. Privacy policy omits Cloudflare Turnstile as a processor while stating nothing unlisted is collected. `site/privacy.html:60–73`.
18. App Store metadata/checklist still written for 1.0; build is 1.3.0 (16). `docs/app-store/metadata.md:94`.
19. Invite-join lumps "no verified email" (PG 22023) into the "invalid or turned off" alert — valid links dead-end for unverified users. `RootView.swift:360`.
20. TabCore floors sub-minor-unit amounts to zero balance rather than rejecting them (only reachable if the DB ever serves sub-scale amounts). `Money.swift`, `BalanceEngine.swift:112–132`. (Codex finding, conditional.)

## 2026-07-18 — Design-confirm items (documented as intended; verify against spec)

- `ConflictResolver` two-tombstone ordering compares `deletedAt` (not `updatedAt`) with writeID tiebreak — code comment says intended.
- `merge` returns `.applyRemote` for any clean local row without timestamp comparison ("server authoritative for clean rows") — intended per doc comment.
- Zero-row UPDATE responses marking rows clean is largely intended: the DB trigger drops stale LWW writes by returning null, and the next pull converges.

## 2026-07-18 — Refuted during verification (not bugs)

- `distributePairs` clawback claim (TabCore) — refuted.
- Money currency-string normalization claim — refuted.
- "aps-environment stuck on development / production push broken" (two variants) — refuted; entitlement setup is correct for archive builds.

No Double-for-money usage found anywhere (both audits checked).

## 2026-07-18 evening — All 20 findings fixed

Every finding was fixed the same day via five Codex (GPT-5.6 Sol) workstreams in isolated worktrees, tracked as GitHub issues #13-#32 (label audit-2026-07-18), reviewed line-by-line and merged one at a time: WS4 backend hardening (findings 7/8/16), WS5 copy+metadata (15/17/18/19), WS3 money+UI (5/13/14/20), WS1 sync data integrity (1/2/6), WS2 sync lifecycle (3/4/9/10/11/12). Final merged state: 155 TabCore + 116 app tests + SQL assembly, all green (250 -> 271 tests). 17 issues closed; #18/#19/#28 stay open pending the gated production steps (schema apply, send-push redeploy). The live database was never touched. Per-workstream details in the five sibling working logs dated today.
