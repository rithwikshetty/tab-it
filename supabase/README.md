# tab Supabase contract

The editable database contract is split across numbered files in `sql/`. `schema.sql` is only a small source map; do not put DDL there.

## Production safety

- Production contains real user data. It is read-only by default.
- This repository provides no database-recreation or destructive-teardown command.
- Never run SQL, migrations, tests, Auth changes, Storage cleanup, Realtime changes, or Edge Function changes against production without explicit approval for the exact operation and verified project target.
- Development and tests use mocks, a local stack, or an explicitly isolated non-production project/branch.
- The deployed baseline migration is immutable. Future changes require new forward-only, compatibility-preserving migrations and a reviewed backup, rollback, and deployment plan.

`bash tests/00_sql_assembly.sh` is safe to run locally because it only checks
checked-in source assembly and does not connect to any database. Do not edit the
split SQL or migration files until the specific production-safe migration plan
has been approved.

The receipt cleanup helper is restricted to explicitly confirmed,
non-production environments. It must never be used with production credentials.

## Client write paths

- Trip creation: call `create_trip_with_self(trip_id, person_id, name)` so the trip and creator person row are transactional and use client-provided UUIDs.
- Add person by email: call `add_trip_person_by_email(trip_id, email, display_name?, person_id?)`. Existing auth users join immediately; otherwise the row remains pending.
- Sign-in claim: call `claim_trip_people_for_current_email()` before pulling trips.
- Suggestions: call `suggest_trip_people(query?, limit?)`; results are limited to people the current user has already shared trips with.
- Expense creation/editing: call `create_expense_with_payments_and_splits(expense, payments, splits)`. It atomically upserts an active expense and replaces both ledgers; edits to soft-deleted expenses are rejected.
- Receipt upload: upload JPEGs to the private `receipts` bucket at `<trip_id>/<expense_id>.jpg`.
- Soft-delete purge: call `purge_soft_deleted_records()` from a service-role scheduled job once the app is ready to enable the 30-day hard-delete policy.

Direct inserts into `trip_people` are not a public client API. RLS intentionally denies them.

## Invariants enforced by Postgres

- Payers, split participants, settlement parties, creators, custom categories, and mute prefs must belong to the target trip.
- Expense payment and split totals must equal the expense amount for active expenses.
- Pending people are matched by normalized email and linked to auth profiles by `claim_trip_people_for_current_email()`.
- Receipt object access is derived from the trip id in the storage object path and joined `trip_people`.
- The purge function deletes only soft-deleted rows older than the cutoff and skips trips that still have expense or settlement rows.

## Test workflow

Run `bash supabase/tests/00_sql_assembly.sh` locally first; it verifies the split SQL sources generate the checked-in baseline. Run pgTAP files only against an isolated non-production database. The test runner defaults to the local Supabase stack and never uses a linked remote project.
