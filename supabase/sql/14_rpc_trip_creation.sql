-- 12. Client RPCs
-- ============================================================================

create or replace function public.create_trip_with_self(
  p_trip_id uuid,
  p_person_id uuid,
  p_name text
)
returns table (
  trip_id uuid,
  person_id uuid
)
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

  if v_email is null or v_email = '' or v_email not like '%@%' then
    raise exception 'A verified email is required to create trips' using errcode = '22023';
  end if;

  if p_trip_id is null or p_person_id is null then
    raise exception 'trip_id and person_id are required' using errcode = '22023';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Trip name is required' using errcode = '22023';
  end if;

  if exists (select 1 from public.trips t where t.id = p_trip_id and t.kind <> 'trip') then
    raise exception 'Group-trip RPC cannot target non-group containers' using errcode = '42501';
  end if;

  select display_name into v_display_name
  from public.profiles
  where id = v_actor;

  v_display_name := left(coalesce(nullif(trim(v_display_name), ''), split_part(v_email, '@', 1)), 60);

  if exists (
    select 1
    from public.trips t
    where t.id = p_trip_id
      and not private.is_profile_trip_member(t.id, v_actor)
      and (
        t.created_by <> v_actor
        -- A removed creator does not regain access by re-running creation.
        or exists (
          select 1 from public.trip_people mine
          where mine.trip_id = t.id
            and mine.user_id = v_actor
            and mine.removed_at is not null
        )
      )
  ) then
    raise exception 'Trip already exists and is not writable by current user' using errcode = '42501';
  end if;

  insert into public.trips (id, name, created_by)
  values (p_trip_id, trim(p_name), v_actor)
  on conflict (id) do update
    set name = excluded.name
    where public.trips.kind = 'trip'
      and (
        public.trips.created_by = v_actor
        or private.is_profile_trip_member(public.trips.id, v_actor)
      );

  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.kind = 'trip') then
    raise exception 'Trip could not be created' using errcode = '42501';
  end if;

  insert into public.trip_people (
    id, trip_id, user_id, email, display_name, invited_by, joined_at
  )
  values (
    p_person_id, p_trip_id, v_actor, v_email, v_display_name, v_actor, clock_timestamp()
  )
  on conflict on constraint trip_people_email_unique do update
    set user_id = v_actor,
        display_name = excluded.display_name,
        joined_at = coalesce(public.trip_people.joined_at, clock_timestamp())
    -- A claimed row never transfers to another account, and an account that
    -- already holds a different row in this trip cannot absorb a second one.
    where public.trip_people.user_id = v_actor
       or (
         public.trip_people.user_id is null
         and not exists (
           select 1 from public.trip_people other
           where other.trip_id = excluded.trip_id
             and other.user_id = v_actor
         )
       )
  returning public.trip_people.id into person_id;

  if person_id is null then
    raise exception 'Person row for % is already claimed by another account', v_email
      using errcode = '42501';
  end if;

  trip_id := p_trip_id;
  return next;
end;
$$;

comment on function public.create_trip_with_self(uuid, uuid, text) is
  'Creates a trip and its creator trip_people row using client-provided UUIDs so offline ledger references remain stable.';
