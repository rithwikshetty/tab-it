# tab — Database tests

Tests cover both the split-SQL assembly contract and database behavior. The shell test verifies generated artifacts; pgTAP SQL files cover schema integrity, constraints, triggers, RLS, and edge cases. Each `.sql` file is self-contained:

- Wraps everything in `BEGIN ... ROLLBACK` so the DB stays clean.
- Declares a `plan(N)` of expected assertions.
- Uses a temp results table to collect every assertion's TAP line, so MCP/CLI execution returns all rows (not just the last one).

## Running

First verify the local SQL source split:

```bash
bash supabase/tests/00_sql_assembly.sh
```

Start and verify the disposable local stack, then run every pgTAP suite:

```bash
bash supabase/scripts/start_local.sh
bash supabase/scripts/run_db_tests.sh
```

The runner verifies the exact `tab-local` stack, then executes each
multi-statement pgTAP file through its project-scoped Postgres container. It
refuses hosted-project link state and remote Supabase environment variables and
never loads `.env` files. SQL tests return one row per assertion plus a final
`1..N` / `# Looks like ...` line.

## Test fixture

Tests that need users insert into `auth.users` directly (the `handle_new_user`
trigger then auto-creates `public.profiles`).
Each file inserts its own users under `00000000-0000-0000-0000-00000000000N` UUIDs. The
inserts at the top of a file name each user and the trips they belong to.

## Files

| File | Tests | Concern |
|------|-------|---------|
| `00_sql_assembly.sh` | 1 | Split SQL source generates the checked-in baseline; `schema.sql` stays small |
| `01_schema.sql` | 53 | Tables/PKs/FKs/RLS-enabled existence (including `trip_invites`), sync-query indexes, realtime publication membership, and email-person RPCs |
| `02_constraints.sql` | 28 | CHECK / UNIQUE / FK constraints plus trip-person ledger invariants |
| `03_triggers.sql` | 16 | `handle_new_user`, sync/touch triggers, transactional trip creation |
| `04_rls.sql` | 36 | RLS allow + deny paths and email-claim joining |
| `05_edge_cases.sql` | 10 | Soft-delete purge, cascade vs restrict, helper-fn behavior |
| `06_expense_payments.sql` | 21 | Transactional expense create/edit RPC with trip-person payments/splits |
| `07_settlements.sql` | 9 | Settlement writes under many dummy expenses, including pending trip people |
| `08_activity_notifications.sql` | 17 | Activity log triggers, read cursor, mute, and unread badge count |
| `09_non_group.sql` | 32 | Non-group containers: resolution, dedup, RLS privacy, claim |
| `10_claim_guards.sql` | 8 | Claimed trip people never transfer between accounts; member signatures stay clean |
| `11_sync_lww.sql` | 29 | Server-side last-write-wins: stale writes skipped, tombstones never resurrected, the trip activity bump keeps a trip's sync stamps, client stamps capped at five minutes ahead |
| `12_rls_deny_gaps.sql` | 11 | Deny paths for expense payments, expense splits, push devices, and mute prefs |
| `13_account_deletion.sql` | 18 | `delete_account_data` purge and anonymisation, including non-group signatures; clients cannot call it |
| `14_membership_management.sql` | 32 | `update_trip_person_email` and `remove_trip_person`, with their deny paths |
| `15_trip_invites.sql` | 30 | Invite link create/revoke/join RPCs and RLS on the invites table |
| `16_rls_deny_paths.sql` | 30 | Deny paths for categories, expenses, settlements, trips, profiles, activity log, push devices, mute prefs and receipt storage, with member allows |
| `17_expense_editor_guard.sql` | 9 | `expenses.last_edited_by` can only name the signed-in writer; RPC, unchanged re-sends and server writes still work |
| `18_receipt_sweep.sql` | 13 | `orphaned_receipt_objects` lists only receipt objects left alone for 30 days that no live expense points at; clients cannot call it; the daily job sends a request only when its URL is configured |
