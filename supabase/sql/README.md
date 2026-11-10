# Split SQL source

The editable Supabase contract lives here. Files are numbered because order matters; `supabase/scripts/build_schema.sh` concatenates them into the generated baseline migration.

## Layout

| File | Owns |
| --- | --- |
| `00_extensions.sql` | Extensions and shared sync trigger helper. |
| `01_private_helpers.sql` | Private RLS/helper functions. |
| `02_profiles.sql` | Profile table, signup trigger, profile RPC. |
| `03_trips_people.sql` | Trips and trip-scoped people tables. |
| `04_categories.sql` | Built-in and trip-scoped categories. |
| `05_expenses.sql` | Expense row table, expense validation, trip activity touch. |
| `06_expense_payments.sql` | Payment ledger table and payment total enforcement. |
| `07_expense_splits.sql` | Split ledger table and split total enforcement. |
| `08_settlements.sql` | Settlement table and validation. |
| `09_activity_log.sql` | Append-only activity log. |
| `10_push_devices_mutes.sql` | Push tokens and trip mute preferences. |
| `11_maintenance_realtime.sql` | Soft-delete purge RPC and realtime publication setup. |
| `12_rls.sql` | Row-level security enablement and policies. |
| `13_receipt_storage.sql` | Receipt bucket and storage policies. |
| `14_rpc_trip_creation.sql` | Transactional trip creation RPC. |
| `15_rpc_trip_people.sql` | Email add, claim, and suggestion RPCs. |
| `16_rpc_expenses.sql` | Transactional expense create/edit RPC. |
| `17_privileges.sql` | Function execute grants/revokes. |
| `18_notifications_push.sql` | Push fan-out: pg_net webhook trigger on activity_log, config table, badge count. |
| `19_rpc_non_group.sql` | Hidden non-group container resolution RPC. |
| `20_account_deletion.sql` | Account data purge called by the `delete-account` edge function. |
| `21_trip_invites.sql` | Trip invite link tokens and join RPCs. |
| `22_receipt_sweep.sql` | Daily removal of receipt objects no expense points at: pg_cron job, orphan list RPC, edge function request. |

## Editing workflow

The numbered files describe the whole database as it should be. Two things are generated from or added beside them:

- `migrations/20260518000000_baseline.sql` is the concatenation of these files. `bash supabase/scripts/build_schema.sh --write` regenerates it, and `bash supabase/tests/00_sql_assembly.sh` fails when it differs from the sources. Production was built from earlier generated SQL, has no baseline entry in its migration history, and never replays this file.
- Each production change also ships as its own forward-only migration in `migrations/`, named with the version it gets in production. It repeats the change as idempotent SQL (`create or replace`, `create index if not exists`), so a local reset applies it harmlessly on top of the regenerated baseline, and production applies it on top of what it already has.

Steps:

1. Edit the narrowest numbered file.
2. Add or update a pgTAP test in `supabase/tests/`, covering both the allowed and the refused path.
3. Regenerate the baseline with `bash supabase/scripts/build_schema.sh --write`.
4. Write the forward-only migration with the same change.
5. Check it locally: `bash supabase/tests/00_sql_assembly.sh`, then `bash supabase/scripts/reset_local.sh` and `bash supabase/scripts/run_db_tests.sh`. Also apply the migration to a local database built from the previous baseline, which is the state production is in.
6. Write the rollout plan in `docs/reports/` (pre-flight checks, backup, apply, verification, rollback) and get explicit approval before anything touches production.

`supabase/schema.sql` is intentionally only a pointer. Do not put DDL there.
