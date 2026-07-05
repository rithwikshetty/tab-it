-- ============================================================================
-- Client RPCs: trip people
-- ============================================================================

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
    set display_name = excluded.display_name,
        -- Re-adding a removed person restores them, keeping their ledger
        -- identity (and claim state) instead of minting a duplicate row.
        removed_at = null
  returning public.trip_people.* into v_person;

  return v_person;
end;
$$;

comment on function public.add_trip_person_by_email(uuid, text, text, uuid) is
  'Adds or updates a pending trip person by email; re-adding a removed person''s email restores them. Existing auth accounts are not linked until that user signs in and claims the email.';

create or replace function public.claim_trip_people_for_current_email()
returns setof public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := private.current_auth_email();
  v_display_name text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' then
    return;
  end if;

  select display_name into v_display_name
  from public.profiles
  where id = v_actor;

  insert into public.profiles (id, display_name)
  values (v_actor, left(coalesce(nullif(trim(v_display_name), ''), split_part(v_email, '@', 1)), 60))
  on conflict (id) do nothing;

  return query
  update public.trip_people tp
  set user_id = v_actor,
      display_name = left(coalesce(nullif(trim(v_display_name), ''), tp.display_name), 60),
      joined_at = clock_timestamp()
  where tp.email = v_email
    and tp.user_id is null
    -- Removed pending rows are not claimable; restoring goes through
    -- add_trip_person_by_email.
    and tp.removed_at is null
    and not exists (
      select 1
      from public.trip_people existing
      where existing.trip_id = tp.trip_id
        and existing.user_id = v_actor
      -- Deliberately counts removed claimed rows: claiming a second row for
      -- the same user would violate trip_people_trip_user_uniq.
    )
  returning tp.*;
end;
$$;

comment on function public.claim_trip_people_for_current_email() is
  'Links pending trip_people rows for auth.uid() email. Called after sign-in before sync pull.';

create or replace function public.suggest_trip_people(
  p_query text default null,
  p_limit int default 8
)
returns table (
  user_id uuid,
  email text,
  display_name text
)
language plpgsql
security definer
stable
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_query text := nullif(trim(p_query), '');
  v_limit int := least(greatest(coalesce(p_limit, 8), 1), 25);
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  return query
  select distinct on (tp.email)
    tp.user_id,
    tp.email,
    tp.display_name
  from public.trip_people tp
  where coalesce(tp.user_id, '00000000-0000-0000-0000-000000000000'::uuid) <> v_actor
    and tp.removed_at is null
    and exists (
      select 1
      from public.trip_people mine
      where mine.trip_id = tp.trip_id
        and mine.user_id = v_actor
        and mine.joined_at is not null
        and mine.removed_at is null
    )
    and (
      v_query is null
      or tp.email ilike '%' || v_query || '%'
      or tp.display_name ilike '%' || v_query || '%'
    )
  order by tp.email, tp.updated_at desc
  limit v_limit;
end;
$$;

comment on function public.suggest_trip_people(text, int) is
  'Suggests people the current user has already shared a trip with. No global user search.';

create or replace function public.update_trip_person_email(
  p_person_id uuid,
  p_email text
)
returns public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := private.normalized_email(p_email);
  v_person public.trip_people;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' or v_email not like '%@%' or char_length(v_email) > 320 then
    raise exception 'A valid email is required' using errcode = '22023';
  end if;

  select tp.* into v_person
  from public.trip_people tp
  join public.trips t on t.id = tp.trip_id
  where tp.id = p_person_id
    and t.kind = 'trip'
    and t.deleted_at is null
  for update of tp;

  if not found then
    raise exception 'Person not found' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(v_person.trip_id, v_actor) then
    raise exception 'Only trip members can edit people' using errcode = '42501';
  end if;

  if v_person.user_id is not null then
    raise exception 'This person already joined with their own account; their email cannot be changed' using errcode = '42501';
  end if;

  if v_person.removed_at is not null then
    raise exception 'This person was removed from the trip' using errcode = '42501';
  end if;

  if v_person.email = v_email then
    return v_person;
  end if;

  if exists (
    select 1 from public.trip_people other
    where other.trip_id = v_person.trip_id
      and other.email = v_email
      and other.id <> v_person.id
  ) then
    raise exception 'Someone in this trip already has that email' using errcode = '23505';
  end if;

  update public.trip_people tp
  set email = v_email
  where tp.id = v_person.id
  returning tp.* into v_person;

  return v_person;
end;
$$;

comment on function public.update_trip_person_email(uuid, text) is
  'Repoints a pending (unclaimed) trip person to a real email so the owner can claim it at sign-in. The main path for linking Splitwise-imported people, who start with synthetic @users.tab emails. Joined or removed people are not editable.';

create or replace function public.remove_trip_person(
  p_person_id uuid
)
returns public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_person public.trip_people;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select tp.* into v_person
  from public.trip_people tp
  join public.trips t on t.id = tp.trip_id
  where tp.id = p_person_id
    and t.kind = 'trip'
    and t.deleted_at is null
  for update of tp;

  if not found then
    raise exception 'Person not found' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(v_person.trip_id, v_actor) then
    raise exception 'Only trip members can remove people' using errcode = '42501';
  end if;

  if v_person.user_id = v_actor then
    raise exception 'You cannot remove yourself from a trip' using errcode = '42501';
  end if;

  if v_person.removed_at is not null then
    return v_person;
  end if;

  update public.trip_people tp
  set removed_at = clock_timestamp()
  where tp.id = v_person.id
  returning tp.* into v_person;

  return v_person;
end;
$$;

comment on function public.remove_trip_person(uuid) is
  'Soft-removes a person from a trip (removed_at). Their ledger rows and balances stay intact; they lose trip access and drop out of pickers. Idempotent. Self-removal is blocked so a trip always keeps at least one active claimed member.';
