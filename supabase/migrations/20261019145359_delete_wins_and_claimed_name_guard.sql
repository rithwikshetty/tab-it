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
