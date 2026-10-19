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
