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

## Editing workflow

1. Add or edit the narrowest numbered file.
2. Add/update a pgTAP test in `supabase/tests/` for behavior changes.
3. Design a new forward-only migration; never rewrite the deployed baseline.
4. Test the proposed change in an explicitly isolated non-production environment.
5. Run `bash supabase/tests/00_sql_assembly.sh` for the local static source check.
6. Obtain explicit approval before any production deployment.

`supabase/schema.sql` is intentionally only a pointer. Do not put DDL there.
