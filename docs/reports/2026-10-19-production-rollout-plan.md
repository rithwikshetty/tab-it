# Production rollout plan: #18, #28, #19, #34

Status: **steps 0 to 3 applied on 19 October 2026** with the owner's approval; results are in `docs/working_log/2026-10-18-expo-rewrite.md` ("production rollout of #18, #28, #19 and #34"). Step 4 is the next TestFlight build. Each production step began by verifying the target is project `gaseuxsieddlksxtdliq`.

| Issue | State on main | What production still needs |
|---|---|---|
| #19 send-push deletes valid device rows on `BadDeviceToken` | Fixed in `5d5017d` | Redeploy the `send-push` edge function; check the APNs secrets |
| #18 `set_sync_fields` can drop a delete | Fixed in `b5ab7dd` | A forward migration replacing the function |
| #28 `add_trip_person_by_email` can rename a claimed member | Fixed in `7dfc06f` | The same forward migration |
| #34 API role grants aren't explicit | Not started | A forward migration stating the grants production already has |

The three changes don't depend on each other or on the app rollout. Steps run in the order below because the first one is read-only and decides whether the others are safe.

## Step 0: read-only inventory (no changes)

Everything later is checked against what this step records, so save every output.

1. `select version, name from supabase_migrations.schema_migrations order by version;`. Production was built from generated SQL plus ad hoc `apply_migration` calls (`docs/working_log/2026-06-06-recreate-db.md`), and the baseline file has been edited since. If the baseline version is missing here, `supabase db push` would try to replay the whole baseline. **Never use `db push` against production** until the history is reconciled; apply migrations through the MCP `apply_migration` tool as earlier production changes did.
2. Function metadata for the rollback copy: owner, `prosecdef`, `proconfig`, `proacl`, `md5(prosrc)`, comment and `pg_get_functiondef` for `public.set_sync_fields()` and `public.add_trip_person_by_email(uuid,text,text,uuid)`. Expected body md5s: `2b7bc484a0772ddd163839b6205f4dc5` and `da82cde5be85556d7cef7174ef973c83` (pre-fix). Any other value means stop and replan: `6e0023d8b73fb329e077d3340f8f3f8a` for `set_sync_fields` would mean last-write-wins never reached production, which is a much bigger change.
3. Which tables `set_sync_fields` fires on, and that they're enabled (11 expected).
4. Grants: the four queries in Appendix C. Each must return 0 findings. Also save a full ACL snapshot of the public schema as the grants rollback copy.
5. Whether `purge_soft_deleted_records` is scheduled (pg_cron jobs). Step 2 lets delayed deletes apply, and a delete can carry an old client `deleted_at`, so a scheduled purge could remove those rows straight away.
6. Edge functions: `supabase functions list --project-ref gaseuxsieddlksxtdliq` (version and date of `send-push`) and `supabase secrets list --project-ref gaseuxsieddlksxtdliq` (names and digests only, never values). Required names: `WEBHOOK_SECRET`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_BUNDLE_ID`, `APNS_P8_KEY`, `APNS_ENV`. Compare digests with local SHA-256 of `production`, `36VWCMM6GL` and `com.rithwikshetty.tab`.
7. Backups: confirm in the dashboard which backup or point-in-time recovery the project has.

Don't run `supabase link`, and don't export `SUPABASE_ACCESS_TOKEN` in a shell that runs local scripts. `supabase/scripts/assert_local_only.sh` refuses both.

## Step 1: push (#19)

**Why first:** the last recorded production `APNS_ENV` is `sandbox` (`docs/working_log/2026-07-14-notification-system-review.md:107`). The App Store app and TestFlight builds hold production APNs tokens. If the value is still `sandbox`, no real user receives pushes, and the deployed function deletes their `push_devices` rows on every activity. The Expo app re-registers on each foreground. The Swift app only re-registers when its token changes or at startup, so its users can stay unregistered.

1. Deploy from a clean main: `supabase functions deploy send-push --no-verify-jwt --project-ref gaseuxsieddlksxtdliq`. `--no-verify-jwt` is required, because pg_net calls the function with a shared secret and no JWT.
2. If step 0 shows `APNS_ENV` isn't `production`: owner decision to set it to `production` and redeploy. This turns on pushes to real users for the first time.
3. If `APNS_TEAM_ID` doesn't match `36VWCMM6GL`: set it to the correct team, after the owner approves.
4. Verify. A POST without the secret returns plain-text `unauthorized`. One expense on a second account reaches the owner's phone, and the `net._http_response` row shows `"sent":1,"pruned":0`. The `push_devices` count is unchanged.
5. Rollback: redeploy from `5d5017d^` (same tree as `8013bac`). That brings back the deleting behaviour, so only do it if the new version fails to boot. Restoring a secret is a separate step. Deleted registrations and missed pushes aren't recovered either way.

## Step 2: functions (#18 and #28)

Behaviour after the change:
- An incoming delete wins over a live row whatever its timestamp, matching both clients' merge rule (`mobile/src/data/merge.ts:69`).
- A claimed member's name can't be overwritten by re-adding their email.

The Expo client needs this. With the old function, an older-timestamped delete is dropped and `updateOne` throws `GONE` (`mobile/src/data/sync.ts:297-306`), so the row retries every sync. The Swift client lost such deletes silently. Deletes already lost aren't recovered.

1. Settle the purge question from step 0 first.
2. Apply in one `apply_migration` call named `delete_wins_and_claimed_name_guard`, as one transaction:
   - the guard (Appendix B), extended to also check owner, `prosecdef`, `proconfig` and `proacl` against the step 0 capture;
   - then the migration (Appendix A).

   `create or replace function` takes no table locks.
3. Verify by re-running the step 0 metadata query. Expected body md5s afterwards: `1b81b89cac5d47c39c70a8a088bf36a7` and `bf3a2abdbef3f9055beca4d0ef720fc7`. Owner, ACL, config and security mode must be unchanged.
4. Rollback: the `pg_get_functiondef` output captured in step 0, not the git text. Rolling back only changes future writes. Deletes already applied stay applied.
5. Commit the same migration file under `supabase/migrations/` once it's applied. It's idempotent, so it replays harmlessly on top of the regenerated baseline locally.

## Step 3: grants (#34)

On 30 October 2026 Supabase stops granting API access to new tables automatically. Its changelog says existing tables keep their grants, so production doesn't break on that date. Local development does break once a CLI release drops `api.auto_expose_new_tables`: config parsing fails, and a fresh reset gives no table privileges, which fails 10 of 15 pgTAP suites.

1. Apply M1 (Appendix C) only if every step 0 grant query returned 0 findings. Then it adds no access production doesn't already have. It keeps `profiles.activity_last_seen_at` unreadable, and has a tripwire that aborts if that boundary isn't intact. Never run a table-level `REVOKE SELECT` on `profiles`, because that also removes the column grants.
2. Verify by re-running the Appendix C checks (0 findings) and comparing the ACL snapshot, which should be unchanged.
3. Rollback: nothing to undo for M1, since it grants only what production already holds. Restore from the step 0 snapshot if anything differs.
4. Then, locally: commit M1 as a migration, remove `api.auto_expose_new_tables` from `supabase/config.toml`, reset, and run all suites.
5. Deferred:
   - **M2:** defaults that revoke on future tables. It needs its own rollback that restores the captured default ACLs; a blanket `GRANT ALL` would widen access.
   - **M3:** removes `anon` and unused table privileges, which is a real tightening.

   Both are separate decisions.

If the owner doesn't approve M1 before the CLI drops the key: remove the key locally, and load the M1 grants through a local-only seed file (`[db.seed] sql_paths`). That was tested with 15 of 15 suites passing.

## Step 4: app build

Build 2.0.0 (18) predates the push-tap fixes (`aed19fe`, `7134e6d`, `6f63619`, `68cfcc0`). Once step 1 makes pushes reach production devices, ship a new TestFlight build with the `testflight` skill and check on a real iPhone that:
- tapping a push opens the expense;
- a second push about the same expense opens it again;
- signing out and back in reopens nothing.

## Owner decisions

1. Approve step 0, the read-only inventory.
2. Approve step 1, the deploy, and decide whether pushes go live (`APNS_ENV=production`), with you as the test recipient.
3. Settle the purge policy, then approve step 2.
4. Approve step 3 M1. Decide on M2 and M3 separately, later.

## Appendix A: forward migration for #18 and #28

```sql
-- Forward-only: replaces two function bodies. No table, column, index, policy,
-- trigger, grant or data changes. CREATE OR REPLACE keeps each function's
-- owner and privileges.
--
-- public.set_sync_fields(): an incoming write that carries deleted_at beats a
-- live row regardless of updated_at. Resurrection stays blocked; live/live and
-- deleted/deleted keep their existing ordering. (GitHub #18)
--
-- public.add_trip_person_by_email(): the email-conflict upsert no longer
-- overwrites display_name of a claimed member (user_id is not null). Unclaimed
-- rows still update and a removed member is still restored. (GitHub #28)

create or replace function public.set_sync_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_deleted timestamptz;
  v_new_deleted timestamptz;
begin
  if tg_op = 'INSERT' then
    new.created_at := clock_timestamp();
    if new.updated_at is null then new.updated_at := clock_timestamp(); end if;
    if new.write_id   is null then new.write_id   := gen_random_uuid();  end if;
    return new;
  end if;

  v_old_deleted := nullif(to_jsonb(old) ->> 'deleted_at', '')::timestamptz;
  v_new_deleted := nullif(to_jsonb(new) ->> 'deleted_at', '')::timestamptz;

  -- Delete-wins: a tombstoned row is never resurrected by a live update.
  if v_old_deleted is not null and v_new_deleted is null then
    return null;
  end if;

  if new.write_id is not distinct from old.write_id then
    -- Metadata-less write: stamp fresh server values (previous behavior).
    new.updated_at := clock_timestamp();
    new.write_id   := gen_random_uuid();
    return new;
  end if;

  -- Client-supplied metadata: last write wins, write_id breaks ties. A write
  -- whose updated_at equals the row's goes to the tiebreaker — clients always
  -- send write_id and updated_at together.
  if new.updated_at is null then
    new.updated_at := clock_timestamp();
  end if;

  if v_old_deleted is not null and v_new_deleted is not null then
    if v_new_deleted < v_old_deleted
       or (v_new_deleted = v_old_deleted and new.write_id::text < old.write_id::text) then
      return null;
    end if;
  elsif v_old_deleted is null and v_new_deleted is null then
    if new.updated_at < old.updated_at
       or (new.updated_at = old.updated_at and new.write_id::text < old.write_id::text) then
      return null;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.set_sync_fields() is
  'BEFORE INSERT/UPDATE trigger for synced tables. Stamps created_at on insert and fills missing updated_at/write_id. On update, delete-wins is unconditional across live/deleted state (live-to-deleted writes apply; resurrection is blocked); live-live writes use updated_at LWW and both-deleted writes use deleted_at LWW, with write_id tiebreakers. Metadata-less updates get fresh server stamps.';

create or replace function public.add_trip_person_by_email(
  p_trip_id uuid,
  p_email text,
  p_display_name text default null,
  p_person_id uuid default null
)
returns public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := private.normalized_email(p_email);
  v_display_name text := nullif(trim(p_display_name), '');
  v_person public.trip_people;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' or v_email not like '%@%' or char_length(v_email) > 320 then
    raise exception 'A valid email is required' using errcode = '22023';
  end if;

  if exists (select 1 from public.trips t where t.id = p_trip_id and t.kind <> 'trip') then
    raise exception 'Group-trip RPC cannot target non-group containers' using errcode = '42501';
  end if;

  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.kind = 'trip' and t.deleted_at is null) then
    raise exception 'Trip not found or deleted' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(p_trip_id, v_actor) then
    raise exception 'Only trip members can add people' using errcode = '42501';
  end if;

  v_display_name := left(coalesce(v_display_name, split_part(v_email, '@', 1)), 60);

  insert into public.trip_people (
    id, trip_id, user_id, email, display_name, invited_by, joined_at
  )
  values (
    coalesce(p_person_id, gen_random_uuid()),
    p_trip_id,
    null,
    v_email,
    v_display_name,
    v_actor,
    null
  )
  on conflict on constraint trip_people_email_unique do update
    set display_name = case
          when public.trip_people.user_id is null then excluded.display_name
          else public.trip_people.display_name
        end,
        -- Re-adding a removed person restores them, keeping their ledger
        -- identity (and claim state) instead of minting a duplicate row.
        removed_at = null
  returning public.trip_people.* into v_person;

  return v_person;
end;
$$;

comment on function public.add_trip_person_by_email(uuid, text, text, uuid) is
  'Adds or updates a pending trip person by email; re-adding a removed person''s email restores them. Existing auth accounts are not linked until that user signs in and claims the email.';
```

## Appendix B: apply-time drift guard (not committed in the migration file)

```sql
-- Fail closed if production has drifted from the definitions this migration
-- was written against. Each function must be either the previous definition
-- (hash below) or already the fixed one.
do $guard$
declare
  v_sync   text;
  v_person text;
begin
  select md5(p.prosrc) into strict v_sync
  from pg_proc p where p.oid = 'public.set_sync_fields()'::regprocedure;
  select md5(p.prosrc) into strict v_person
  from pg_proc p
  where p.oid = 'public.add_trip_person_by_email(uuid, text, text, uuid)'::regprocedure;

  if v_sync not in ('2b7bc484a0772ddd163839b6205f4dc5',    -- previous
                    '1b81b89cac5d47c39c70a8a088bf36a7') then -- fixed
    raise exception 'set_sync_fields() differs from the expected previous definition (md5 %)', v_sync;
  end if;
  if v_person not in ('da82cde5be85556d7cef7174ef973c83',  -- previous
                      'bf3a2abdbef3f9055beca4d0ef720fc7') then -- fixed
    raise exception 'add_trip_person_by_email() differs from the expected previous definition (md5 %)', v_person;
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'trip_people' and column_name = 'removed_at'
  ) then
    raise exception 'public.trip_people.removed_at is missing';
  end if;
end
$guard$;
```

## Appendix C: grants pre-check (read-only) and M1

```sql
-- READ-ONLY. Expect 0 rows from each of the first three queries on production.
-- 1) Privileges the migration grants that production does NOT already hold (rows = migration would add access).
with want(role, rel, priv) as (
  select r, t, p
  from unnest(array['trips','trip_people','categories','expenses','expense_payments','expense_splits','settlements','activity_log','push_devices','trip_mute_prefs','trip_invites']) t,
       unnest(array['SELECT','INSERT','UPDATE','DELETE']) p,
       (values ('authenticated')) v(r)
  union all select 'authenticated','profiles', p from unnest(array['INSERT','UPDATE','DELETE']) p
  union all select 'authenticated','visible_profiles','SELECT'
  union all select 'service_role','activity_log','SELECT'
  union all select 'service_role','push_devices','SELECT'
  union all select 'service_role','push_devices','DELETE'
)
select role, rel, priv, 'MISSING in production' as finding
from want where not has_table_privilege(role, ('public.'||rel)::regclass, priv);

-- 2) service_role EXECUTE on the purge function (missing = migration would add access).
select 'service_role' as role, 'purge_soft_deleted_records' as fn, 'MISSING in production' as finding
where not has_function_privilege('service_role', to_regprocedure('public.purge_soft_deleted_records(timestamptz)'), 'EXECUTE');

-- 3) The profiles read boundary must already hold (rows = boundary is NOT intact; stop).
select 'authenticated can read profiles.activity_last_seen_at' as finding
where has_table_privilege('authenticated', 'public.profiles', 'SELECT')
   or has_column_privilege('authenticated', 'public.profiles', 'activity_last_seen_at', 'SELECT');

-- 4) Objects the migration names must exist (every value must be non-null) and RLS must be on.
select to_regclass('public.trip_invites') as trip_invites, to_regclass('public.visible_profiles') as visible_profiles,
       to_regprocedure('public.purge_soft_deleted_records(timestamptz)') as purge_fn;
select c.relname, pg_get_userbyid(c.relowner) as owner, c.relrowsecurity as rls_on
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' order by 1;

-- Explicit Data API privileges for the public schema.
--
-- The API roles' table privileges used to come from Supabase's default
-- privileges at table creation, which a database built from the baseline alone
-- does not get. This states them. Each statement grants a privilege the
-- deployed project already holds, so it changes nothing there.
--
-- Row access is decided by RLS (supabase/sql/12_rls.sql, 21_trip_invites.sql),
-- so authenticated holds the four DML privileges on every table and RLS allows
-- or filters each operation. public.profiles is the exception: it is read
-- column by column (supabase/sql/17_privileges.sql), so no table-level SELECT is
-- granted and activity_last_seen_at stays private.

-- Tripwire: stop (and roll back) rather than widen the profiles read boundary.
do $$
begin
  if has_table_privilege('authenticated', 'public.profiles', 'SELECT')
     or has_column_privilege('authenticated', 'public.profiles', 'activity_last_seen_at', 'SELECT') then
    raise exception 'authenticated must not be able to read profiles.activity_last_seen_at';
  end if;
end
$$;

-- authenticated (signed-in users)
grant select, insert, update, delete on
  public.trips, public.trip_people, public.categories,
  public.expenses, public.expense_payments, public.expense_splits,
  public.settlements, public.activity_log,
  public.push_devices, public.trip_mute_prefs, public.trip_invites
  to authenticated;
grant insert, update, delete on public.profiles to authenticated;

-- service_role (edge functions): send-push reads activity_log and prunes
-- push_devices; the purge job (supabase/README.md) calls the purge RPC.
grant select         on public.activity_log to service_role;
grant select, delete on public.push_devices to service_role;
grant execute on function public.purge_soft_deleted_records(timestamptz) to service_role;

-- anon: nothing in public is meant for signed-out requests.
```
