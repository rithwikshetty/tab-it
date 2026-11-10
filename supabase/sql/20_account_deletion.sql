-- 20. Account deletion (App Store 5.1.1(v))
-- ============================================================================
-- Called by the delete-account edge function with the service role, before it
-- deletes the auth.users row via the admin API. Hard-deletes everything only
-- the user could see, anonymizes their identity in shared trips, and returns
-- receipt storage paths for the edge function to remove (storage objects
-- cannot be deleted from SQL).

create or replace function public.delete_account_data(p_user uuid)
returns table (receipt_path text)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_sole_trips uuid[];
begin
  if p_user is null then
    raise exception 'p_user is required';
  end if;

  -- Trips where the user is a claimed member and nobody else ever claimed one:
  -- invisible to everyone else, so they go entirely (regardless of soft-delete
  -- state). Pending email-only people cannot see a trip.
  select coalesce(array_agg(t.id), '{}') into v_sole_trips
  from public.trips t
  where exists (
          select 1 from public.trip_people tp
          where tp.trip_id = t.id and tp.user_id = p_user
        )
    and not exists (
          select 1 from public.trip_people tp
          where tp.trip_id = t.id and tp.user_id is not null and tp.user_id <> p_user
        );

  -- Surface receipt paths before the expense rows go.
  return query
    select e.receipt_storage_path
    from public.expenses e
    where e.trip_id = any (v_sole_trips)
      and e.receipt_storage_path is not null;

  -- Order matters: payments/splits cascade from expenses, settlements
  -- restrict-reference trip_people, and the member-left activity trigger
  -- inserts a row referencing the trip — so people go before trips.
  delete from public.expenses    where trip_id = any (v_sole_trips);
  delete from public.settlements where trip_id = any (v_sole_trips);
  delete from public.trip_people where trip_id = any (v_sole_trips);
  delete from public.trips       where id      = any (v_sole_trips);

  -- Shared trips keep their ledger rows (they are the group's data). The
  -- user's claimed identity rows lose the personal email; the trip-scoped
  -- display name stays as the ledger label.
  --
  -- A non-group container's member_signature lists its participants' emails,
  -- so the user's email is swapped for the same scrubbed address, keeping the
  -- sorted '|'-joined form resolve_or_create_non_group_container builds. The
  -- scrubbed address embeds the person id, so the new signature is unique and
  -- a later account with the old email gets a fresh container.
  update public.trips t
  set member_signature = (
    select string_agg(e, '|' order by e)
    from unnest(array_replace(
      string_to_array(t.member_signature, '|'),
      tp.email,
      'deleted-' || tp.id || '@account-deleted.invalid'
    )) as e
  )
  from public.trip_people tp
  where tp.trip_id = t.id
    and tp.user_id = p_user
    and t.kind = 'non_group';

  update public.trip_people tp
  set email = 'deleted-' || tp.id || '@account-deleted.invalid'
  where tp.user_id = p_user;

  delete from public.push_devices    where user_id = p_user;
  delete from public.trip_mute_prefs where user_id = p_user;

  -- Ghost the profile: shared-trip ledger rows restrict-reference it, so it
  -- stays — anonymized and no longer tied to any auth identity.
  update public.profiles
  set display_name = 'Deleted user',
      avatar_url = null,
      activity_last_seen_at = null,
      deleted_at = now()
  where id = p_user;
end;
$$;

comment on function public.delete_account_data(uuid) is
  'Account-deletion purge: hard-deletes sole-member trips, scrubs identity from shared trips, ghosts the profile. Service-role only; the edge function deletes the auth user afterwards.';

revoke execute on function public.delete_account_data(uuid) from public, anon, authenticated;
grant  execute on function public.delete_account_data(uuid) to service_role;


-- ============================================================================
