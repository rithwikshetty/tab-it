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
trigger then auto-creates `public.profiles`). Fixture UUIDs:

| Role  | UUID                                   | Role in fixture                                       |
|-------|----------------------------------------|-------------------------------------------------------|
| Alice | `00000000-0000-0000-0000-000000000001` | Trip creator + joined person in "Lisbon"              |
| Bob   | `00000000-0000-0000-0000-000000000002` | Joined person in "Lisbon"                             |
| Carol | `00000000-0000-0000-0000-000000000003` | Non-member (used to assert RLS denial paths)          |
| Dave  | `00000000-0000-0000-0000-000000000004` | Non-member, owns their own trip "Solo"                |

## Files

| File                      | Tests | Concern                                                |
|---------------------------|-------|--------------------------------------------------------|
| `00_sql_assembly.sh`      | 1     | Split SQL source generates the checked-in baseline; `schema.sql` stays small |
| `01_schema.sql`           | 46    | Tables/PKs/FKs/RLS-enabled existence, realtime publication membership, and email-person RPCs |
| `02_constraints.sql`      | 18    | CHECK / UNIQUE / FK constraints plus trip-person ledger invariants |
| `03_triggers.sql`         | 9     | `handle_new_user`, sync/touch triggers, transactional trip creation |
| `04_rls.sql`              | 16    | RLS allow + deny paths and email-claim joining          |
| `05_edge_cases.sql`       | 10    | Soft-delete purge, cascade vs restrict, helper-fn behavior |
| `06_expense_payments.sql` | 18    | Transactional expense create/edit RPC with trip-person payments/splits |
| `07_settlements.sql`      | 9     | Settlement writes under many dummy expenses, including pending trip people |
