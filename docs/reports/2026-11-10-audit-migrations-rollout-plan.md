# Production rollout: audit database fixes (10 November 2026)

Status: **applied to production on 10 November 2026**, project `gaseuxsieddlksxtdliq`, on the owner's instruction.

Five forward-only migrations, in apply order:

| # | File | Changes | Data touched |
|---|---|---|---|
| M1 | `supabase/migrations/20261110055639_trip_activity_bump_and_clock_cap.sql` | Body of `public.set_sync_fields()` | None |
| M2 | `supabase/migrations/20261110055709_expense_editor_guard.sql` | Body of `public.validate_expense_row()` | None |
| M3 | `supabase/migrations/20261110055715_account_deletion_signature_scrub.sql` | Body of `public.delete_account_data(uuid)` | None at apply time |
| M4 | `supabase/migrations/20261110055720_sync_query_indexes.sql` | Two new indexes | None |
| M5 | `supabase/migrations/20261110055757_receipt_sweep.sql` | `pg_cron`, two new functions, one daily job | None at apply time. The job removes orphaned receipt files. |

The five don't depend on each other. None of them changes a table, column, policy, trigger, grant or the signature of an existing function. M5 adds `public.orphaned_receipt_objects`, which `mobile/src/lib/database.types.ts` lists.

Each file name carries the version production recorded for it.

## Result

Pre-flight on the day:
- The migration history held 56 entries, ending at `20261019145418`.
- The three function bodies hashed to the expected "now" values in 0.2, and `set_sync_fields()` was on 11 enabled triggers.
- 0.4 found neither index name in use. 0.5 found no row stamped in the future. 0.6 found no container, so no signature needed a data fix.
- The `receipts` bucket held 7 objects from May and June 2026. The expense row of every one was gone.

| # | Version | Checked after apply |
|---|---|---|
| M1 | `20261110055639` | `set_sync_fields()` body md5 `38becba23ac0be7939b92a8b2a597935`. Owner, config, ACL and the 11 enabled triggers unchanged. |
| M2 | `20261110055709` | `validate_expense_row()` body md5 `e508d1ac3bda2cdd97a15f32b6a02c34`. Owner, config and ACL unchanged. |
| M3 | `20261110055715` | `delete_account_data(uuid)` body md5 `58018d3820be29f117ce2a1029490c1f`. ACL still `postgres` and `service_role` only. |
| M4 | `20261110055720` | Both indexes exist with the definitions in step 4. |
| M5 | `20261110055757` | `pg_cron` 1.6.4 installed. Job `sweep-receipts` active at `17 3 * * *`. Edge function `sweep-receipts` deployed and answers 401 without the secret. A run requested by hand returned `{"found":7,"removed":7}` and left the bucket empty. |

Row counts in `trips` and `expenses` were the same before and after. The by-hand behaviour checks in steps 1 and 2 have not been run against production. The function bodies there hash to the ones the local suites passed against.

## How this was tested locally

All of it ran on the local Docker stack (`tab-local`), never against production.

1. **Production's state.** `reset_local.sh` with `supabase/migrations/` holding only the committed baseline and the two October migrations. That is the schema production runs. `set_sync_fields()` hashed to `1b81b89cac5d47c39c70a8a088bf36a7`, the md5 production recorded after the October rollout.
2. **Apply on top.** Each of M1 to M4 ran through `psql --single-transaction` twice. The second run was a no-op, apart from M4's "already exists, skipping" notices. Owner, `SECURITY DEFINER` mode, `search_path` and ACLs of the three functions were unchanged.
3. **Full suite on that database.** All 17 pgTAP suites passed, 389 assertions.
4. **The tests catch the defects.** On a fresh copy of production's state without M1 to M4, the new assertions fail exactly where the defects are:
   - `11_sync_lww.sql`: 6 of 29 fail (rename lost after an expense; future stamps not capped).
   - `13_account_deletion.sql`: 2 of 18 fail (signature keeps the email; a new account matches the old container).
   - `17_expense_editor_guard.sql`: 2 of 9 fail (forged editor on update and on insert).
5. **Fresh build equals production plus migrations.** `reset_local.sh` with the regenerated baseline and all six migrations. `pg_dump --schema-only` of `public` and `private` matched the step 3 database line for line, apart from pg_dump's random `\restrict` token. The function hashes matched too. All 17 suites passed again, 389 assertions, and `00_sql_assembly.sh` passed.
6. **M5.** Applied twice through `psql --single-transaction` on that database; the second run changed nothing. `18_receipt_sweep.sql` passed, 13 assertions. With real files uploaded to local Storage, the edge function refused a call without the secret, removed the one aged orphan, and kept the photo a live expense pointed at and an orphan uploaded that day. `private.request_receipt_sweep()` reached the function through `pg_net` and got `{"found":1,"removed":1}`. After a fresh `reset_local.sh`, all 18 suites passed, 402 assertions.

## Step 0: read-only pre-flight (no changes)

Save every output. The rollback copies come from here.

```sql
-- 0.1 Migration history. Expect the two October versions at the end
-- (20261019145359, 20261019145418) and no baseline version, so never use db push.
select version, name from supabase_migrations.schema_migrations order by version;

-- 0.2 Function metadata and the rollback copies.
select p.oid::regprocedure as fn,
       pg_get_userbyid(p.proowner) as owner,
       p.prosecdef, p.proconfig, p.proacl,
       md5(p.prosrc) as body_md5,
       obj_description(p.oid, 'pg_proc') as comment,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
where p.oid in ('public.set_sync_fields()'::regprocedure,
                'public.validate_expense_row()'::regprocedure,
                'public.delete_account_data(uuid)'::regprocedure)
order by 1::text;
```

Expected values for 0.2:

| Function | Owner | Security definer | `proconfig` | ACL | Body md5 now | Body md5 after |
|---|---|---|---|---|---|---|
| `set_sync_fields()` | postgres | false | `{search_path=public}` | `{postgres=X/postgres,service_role=X/postgres}` | `1b81b89cac5d47c39c70a8a088bf36a7` | `38becba23ac0be7939b92a8b2a597935` |
| `validate_expense_row()` | postgres | true | `{"search_path=public, private"}` | same | `f35d2a3690e4fb45937799e1ab079a56` | `e508d1ac3bda2cdd97a15f32b6a02c34` |
| `delete_account_data(uuid)` | postgres | true | `{"search_path=public, private"}` | same | `9c2ecacaffced9082b31f8d889552152` | `58018d3820be29f117ce2a1029490c1f` |

The ACLs above are from the local stack. Production's ACL may list more roles, and that is fine, because `create or replace` keeps it. Only the body md5 matters for the go/no-go. The October rollout confirmed the `set_sync_fields` value on production. The other two "now" values come from git at `759faa8` and haven't been checked on production yet. Any other value means stop and replan.

```sql
-- 0.3 set_sync_fields fires on 11 tables, all enabled ('O').
select c.relname, t.tgname, t.tgenabled
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where t.tgfoid = 'public.set_sync_fields()'::regprocedure order by 1;

-- 0.4 Index names are free, and the table sizes behind M4's plain CREATE INDEX.
select indexname, indexdef from pg_indexes
where schemaname = 'public'
  and indexname in ('activity_log_timestamp_idx', 'trip_people_pending_email_idx');  -- expect 0 rows
select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) as size
from pg_stat_user_tables
where schemaname = 'public' and relname in ('activity_log', 'trip_people');

-- 0.5 Rows already stamped in the future. M1 does not rewrite them; they keep
-- winning last-write-wins until their stamp passes.
select 'trips' as tbl, count(*) filter (where updated_at > now() + interval '5 minutes') as future_updated,
       count(*) filter (where deleted_at > now() + interval '5 minutes') as future_deleted from public.trips
union all select 'expenses', count(*) filter (where updated_at > now() + interval '5 minutes'),
       count(*) filter (where deleted_at > now() + interval '5 minutes') from public.expenses
union all select 'settlements', count(*) filter (where updated_at > now() + interval '5 minutes'),
       count(*) filter (where deleted_at > now() + interval '5 minutes') from public.settlements
union all select 'categories', count(*) filter (where updated_at > now() + interval '5 minutes'),
       count(*) filter (where deleted_at > now() + interval '5 minutes') from public.categories
union all select 'profiles', count(*) filter (where updated_at > now() + interval '5 minutes'),
       count(*) filter (where deleted_at > now() + interval '5 minutes') from public.profiles
union all select 'trip_people', count(*) filter (where updated_at > now() + interval '5 minutes'), 0 from public.trip_people
union all select 'expense_payments', count(*) filter (where updated_at > now() + interval '5 minutes'), 0 from public.expense_payments
union all select 'expense_splits', count(*) filter (where updated_at > now() + interval '5 minutes'), 0 from public.expense_splits
union all select 'trip_mute_prefs', count(*) filter (where updated_at > now() + interval '5 minutes'), 0 from public.trip_mute_prefs
union all select 'push_devices', count(*) filter (where updated_at > now() + interval '5 minutes'), 0 from public.push_devices
union all select 'trip_invites', count(*) filter (where updated_at > now() + interval '5 minutes'), 0 from public.trip_invites;

-- 0.6 Non-group containers whose signature still lists a deleted account's
-- email.
select t.id, t.member_signature,
       string_agg(tp.email, '|' order by tp.email) as rebuilt_signature
from public.trips t
join public.trip_people tp on tp.trip_id = t.id
where t.kind = 'non_group'
group by t.id, t.member_signature
having bool_or(tp.email like 'deleted-%@account-deleted.invalid'
               and not (tp.email = any (string_to_array(t.member_signature, '|'))));
```

0.7 Backups. M1 to M5 change no table row, so the function definitions captured in 0.2 are the undo for M1 to M3. The same text is in git at `759faa8`. The dashboard's backup state was not checked on the day.

Don't run `supabase link`, and don't export `SUPABASE_ACCESS_TOKEN` in a shell that runs local scripts. `supabase/scripts/assert_local_only.sh` refuses both.

## Apply method

Each migration ran through `supabase db query --linked --project-ref gaseuxsieddlksxtdliq -f <file>`. The CLI sends the file to the Management API as one batch, which Postgres runs as one transaction. The file held three things in order: the drift guard from Appendix A, the migration file's text, and an insert into `supabase_migrations.schema_migrations` with the version, the name and the migration text. If the guard raises, nothing applies and no history row is written.

The command leaves `supabase/.temp/linked-project.json` behind. Delete it afterwards, because `supabase/scripts/assert_local_only.sh` refuses to run local scripts while it exists.

Never use `supabase db push`. Production's history has no baseline version, so it would try to replay the whole baseline.

## Step 1: M1, trip activity bump and clock cap

**What changes.** Two things in `set_sync_fields()`.

1. A trips update that changes only `last_activity_at` keeps the trip's `updated_at` and `write_id`. `touch_trip_last_activity()` makes that update after every expense and settlement write.
2. On the client-metadata path (insert, or an update that brings a new `write_id`), `updated_at` and `deleted_at` are capped at `clock_timestamp() + 5 minutes`. A re-sent `deleted_at` that equals the stored one is left alone.

**Why.** Before M1, an expense written at T2 restamped the trip at T2. A rename a phone stamped at T1 < T2 then lost last-write-wins and was dropped. The Expo app's `updateOne` got zero rows and showed "This was deleted, or you no longer have access to it." A phone whose clock ran ahead also won every later edit of the rows it touched, with no limit.

**Expo client.**
- Pulls are full, not keyed on `updated_at`, so other phones still see the new `last_activity_at`.
- A clean local trip takes the server row whole. A dirty one keeps its edit and takes `max(last_activity_at)` (`mobile/src/data/merge.ts`, the `maxTimestamp` branch).
- A capped `updated_at` is safe. The client acknowledges a push by `write_id`. On the next pull the row is clean, and the server's value replaces the local one. With the same `write_id` and a dirty row, `resolveConflict` returns `"same"` and the row is acknowledged.

**Older Swift clients.**
- Pulls are full. `SyncMerge.apply(TripDTO)` advances `lastActivityAt` to the newer value even when the local version wins or the `writeID` matches. That was confirmed in the Swift source at `9bbf17d^`.
- Swift acknowledges by `pushedWriteID`, so a capped stamp behaves as it does for Expo.

**Server side.**
- `log_trip_activity()` only logs a name change.
- `trips_active_idx` is on `last_activity_at`, which still changes.
- Nothing else reads `trips.updated_at`.

**Limits.**
- A phone whose clock runs ahead still wins for up to five minutes.
- Rows already stamped in the future (0.5) keep that stamp.

**Verify after apply.**

```sql
select md5(prosrc) from pg_proc where oid = 'public.set_sync_fields()'::regprocedure;
-- expect 38becba23ac0be7939b92a8b2a597935
```

Re-run 0.2 and 0.3: owner, ACL, config and the 11 enabled triggers must be unchanged. Then check the behaviour by hand:
1. Rename a trip on the Expo app in airplane mode.
2. Add an expense to the same trip from a second account.
3. Reconnect the first phone. The rename must apply with no error badge.

**Rollback.** Run the `definition` column captured for `set_sync_fields()` in 0.2. It starts with `CREATE OR REPLACE FUNCTION`, so paste it as is. Fallback: the function text in `supabase/migrations/20261019145359_delete_wins_and_claimed_name_guard.sql`, which is the definition currently live. Rolling back only changes future writes.

## Step 2: M2, expense editor guard

**What changes.** In `validate_expense_row()`, when `auth.uid()` is not null:
- an insert may set `last_edited_by` only to null or `auth.uid()`;
- an update that changes `last_edited_by` must set it to `auth.uid()`.

Requests without a user (service role, maintenance) are not limited. The error is `42501`, "expenses.last_edited_by must be the current user".

**Why.** A direct REST update or insert could name any current or past trip member as the last editor.

**Expo client.** Direct expense updates send only `deleted_at`, `updated_at` and `write_id`. Creates and edits go through `create_expense_with_payments_and_splits`, which writes `auth.uid()` itself. Imports from Splitwise and from the legacy Swift store use the same RPC.

**Older Swift clients.** Their only direct expense write is the tombstone update, which doesn't touch `last_edited_by`. Everything else goes through the RPC.

**Not checked.** Existing rows are not checked or changed.

**Verify after apply.** The body md5 is `e508d1ac3bda2cdd97a15f32b6a02c34`. Re-run 0.2. Then edit an expense in the app and check that `last_edited_by` is your own id.

**Rollback.** Run the `definition` captured for `validate_expense_row()` in 0.2.

## Step 3: M3, account deletion signature scrub

**What changes.** `delete_account_data(p_user)` also rewrites `member_signature` of the user's non-group containers. The function already scrubs the user's email in `trip_people.email` to `deleted-<person id>@account-deleted.invalid`. M3 swaps that same address into the signature and re-sorts it the way `resolve_or_create_non_group_container()` builds it (`string_agg(e, '|' order by e)`). The address embeds the person id, so it can't collide on `trips_non_group_signature_uniq`. It applies to soft-deleted containers too.

**Why.** Before M3, other members could still read the deleted user's email in the signature. A new account with the same email also resolved to the old container, along with its history.

**Expo client.** The rewrite is a metadata-less update, so the trip gets a fresh `updated_at` and `write_id`, and clients take the new signature on their next pull. `new-expense.tsx` matches local containers by signature. A container with a deleted member no longer matches a fresh set of emails, so the app asks the server, which is the intended result.

**Older Swift clients.** Swift resolves non-group containers through the server RPC only. It stores the pulled signature without using it for matching.

**Verify after apply.** The body md5 is `58018d3820be29f117ce2a1029490c1f`. Re-run 0.2. The ACL must still be `postgres` and `service_role` only. The next real account deletion should leave no row in query 0.6.

**Rollback.** Run the `definition` captured for `delete_account_data(uuid)` in 0.2. Signatures already rewritten stay rewritten. Putting the deleted email back would undo the point of the change.

## Step 4: M4, sync query indexes

**What changes.**
- `activity_log_timestamp_idx` on `activity_log(timestamp desc)`, for the clients' feed pull (`timestamp >= cutoff order by timestamp desc limit 300`).
- `trip_people_pending_email_idx` on `trip_people(email) where user_id is null`, for `claim_trip_people_for_current_email()`, which runs before every full sync.

**Why a plain create is fine.** Both tables are small (check 0.4), so `CREATE INDEX` holds its write lock for well under a second. `CONCURRENTLY` can't run inside a migration transaction. If 0.4 shows either table above roughly a million rows, stop and run `create index concurrently` by hand instead.

**Clients.** No change for either app.

**Verify after apply.** Run 0.4 again: both indexes exist with these definitions.
- `CREATE INDEX activity_log_timestamp_idx ON public.activity_log USING btree ("timestamp" DESC)`
- `CREATE INDEX trip_people_pending_email_idx ON public.trip_people USING btree (email) WHERE (user_id IS NULL)`

**Rollback.**

```sql
drop index if exists public.activity_log_timestamp_idx;
drop index if exists public.trip_people_pending_email_idx;
```

## Step 5: M5, receipt sweep

**What changes.**
- `pg_cron` is enabled.
- `public.orphaned_receipt_objects(p_limit, p_cutoff)` lists objects in the `receipts` bucket that are named like a receipt, that no live expense points at, and where neither the object nor its expense has changed since the cutoff. The cutoff defaults to 30 days ago and the limit to 500. Only `service_role` can call it.
- `private.request_receipt_sweep()` posts to the URL in `private.app_config.receipt_sweep_url`, with `push_webhook_secret` in the `x-webhook-secret` header. With no URL it does nothing.
- The cron job `sweep-receipts` calls that function at 03:17 UTC every day.
- The `sweep-receipts` edge function checks the header against `WEBHOOK_SECRET`, asks for the list and removes those objects through the Storage API. It is deployed with `--no-verify-jwt`, like `send-push`.

**Why.** Removing a receipt, or deleting its expense, left the photo in Storage. The storage policies allow a delete only while a live expense still points at the object, so no client could remove it. `storage.objects` also refuses a direct SQL delete (`protect_objects_delete`), which is why the removal goes through an edge function.

**Why 30 days.** A phone that was offline can push a copy of the expense that still names the photo, and under last-write-wins that copy can win. The wait is counted from the last change to the expense, and to the object.

**Clients.** No change for either app. Every object the sweep removes is one the read policy already refuses to serve.

**Config, set once outside the migration.**

```sql
insert into private.app_config (key, value)
values ('receipt_sweep_url', 'https://gaseuxsieddlksxtdliq.supabase.co/functions/v1/sweep-receipts')
on conflict (key) do update set value = excluded.value;
```

**Verify.**

```sql
select schedule, command, active from cron.job where jobname = 'sweep-receipts';
select count(*) from public.orphaned_receipt_objects();          -- what the next run would remove
select status_code, content from net._http_response order by id desc limit 1;  -- after a run
```

**Turn off.** `delete from private.app_config where key = 'receipt_sweep_url';` makes the job do nothing. `select cron.unschedule('sweep-receipts');` removes the job.

**Rollback.** Unschedule the job, then drop `private.request_receipt_sweep()` and `public.orphaned_receipt_objects(integer, timestamptz)`, and delete the edge function. Files the sweep removed cannot be restored.

## Signatures of accounts deleted before M3

Query 0.6 lists non-group containers whose signature still holds a deleted account's email. It returned no rows on 10 November, so no data fix was run.

## Changes outside the database

- `supabase/config.toml` is local stack configuration only:
  - The auth redirect allow-list is `com.rithwikshetty.tab://auth-callback`.
  - `[functions.send-push] verify_jwt = false` matches how send-push is deployed (`--no-verify-jwt`).
  - `delete-account` needs no section. The default `verify_jwt = true` is how it is deployed, and the function checks the caller's token itself with `auth.getUser()`.
  - Production's redirect allow-list lives in the dashboard. Nothing here changes it.
- `supabase/scripts/clear_receipts_storage.sh` is deleted.
- `[functions.sweep-receipts] verify_jwt = false` matches how sweep-receipts is deployed.

## Appendix A: apply-time drift guards (not in the committed files)

Each guard ran in front of its migration, in the same transaction.

```sql
-- Guard for M1
do $guard$
declare v text;
begin
  select md5(p.prosrc) into strict v from pg_proc p where p.oid = 'public.set_sync_fields()'::regprocedure;
  if v not in ('1b81b89cac5d47c39c70a8a088bf36a7',    -- current
               '38becba23ac0be7939b92a8b2a597935') then -- fixed
    raise exception 'set_sync_fields() differs from the expected definition (md5 %)', v;
  end if;
  if (select count(*) from pg_trigger where tgfoid = 'public.set_sync_fields()'::regprocedure and tgenabled = 'O') <> 11 then
    raise exception 'set_sync_fields() is not on the expected 11 enabled triggers';
  end if;
end
$guard$;

-- Guard for M2
do $guard$
declare v text;
begin
  select md5(p.prosrc) into strict v from pg_proc p where p.oid = 'public.validate_expense_row()'::regprocedure;
  if v not in ('f35d2a3690e4fb45937799e1ab079a56',    -- current
               'e508d1ac3bda2cdd97a15f32b6a02c34') then -- fixed
    raise exception 'validate_expense_row() differs from the expected definition (md5 %)', v;
  end if;
end
$guard$;

-- Guard for M3
do $guard$
declare v text;
begin
  select md5(p.prosrc) into strict v from pg_proc p where p.oid = 'public.delete_account_data(uuid)'::regprocedure;
  if v not in ('9c2ecacaffced9082b31f8d889552152',    -- current
               '58018d3820be29f117ce2a1029490c1f') then -- fixed
    raise exception 'delete_account_data() differs from the expected definition (md5 %)', v;
  end if;
  if to_regclass('public.trips_non_group_signature_uniq') is null then
    raise exception 'trips_non_group_signature_uniq is missing';
  end if;
end
$guard$;

-- Guard for M4: stop if an index with either name exists with another definition.
do $guard$
begin
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'activity_log_timestamp_idx'
             and indexdef <> 'CREATE INDEX activity_log_timestamp_idx ON public.activity_log USING btree ("timestamp" DESC)') then
    raise exception 'activity_log_timestamp_idx exists with a different definition';
  end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'trip_people_pending_email_idx'
             and indexdef <> 'CREATE INDEX trip_people_pending_email_idx ON public.trip_people USING btree (email) WHERE (user_id IS NULL)') then
    raise exception 'trip_people_pending_email_idx exists with a different definition';
  end if;
end
$guard$;

-- Guard for M5: the helpers it builds on exist, and the sweep is not there yet.
do $guard$
begin
  if to_regprocedure('private.receipt_object_expense_id(text)') is null
     or to_regprocedure('private.config(text)') is null
     or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or to_regclass('private.app_config') is null then
    raise exception 'receipt sweep prerequisites are missing';
  end if;
  if to_regprocedure('public.orphaned_receipt_objects(integer, timestamptz)') is not null
     or to_regprocedure('private.request_receipt_sweep()') is not null then
    raise exception 'receipt sweep functions already exist';
  end if;
end
$guard$;
```

## Appendix B: the migrations

The committed files are the source of truth. They ran as they are, after their guard:

- `supabase/migrations/20261110055639_trip_activity_bump_and_clock_cap.sql`
- `supabase/migrations/20261110055709_expense_editor_guard.sql`
- `supabase/migrations/20261110055715_account_deletion_signature_scrub.sql`
- `supabase/migrations/20261110055720_sync_query_indexes.sql`
- `supabase/migrations/20261110055757_receipt_sweep.sql`

Each function body in them is byte-identical to its `supabase/sql/` source, which is why the md5s above match on a fresh local build and on a database migrated from production's state.
