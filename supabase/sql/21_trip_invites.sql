-- 21. Trip invite links
-- ============================================================================
-- A trip has at most one active secret invite link. Anyone who opens the link
-- in the app and signs in becomes a joined trip member — the link is an
-- authenticated door into the trip, with no claim/merge step. Email pre-add +
-- auto-claim (15_rpc_trip_people.sql) is unchanged and complements this.
--
-- The token is the whole secret: possession grants membership. Members can
-- revoke the active link at any time; the next share mints a fresh token.
-- Invites are not client-synced — the app fetches them on demand via RPC, and
-- all writes go through SECURITY DEFINER RPCs below.

create table public.trip_invites (
  id         uuid primary key default gen_random_uuid(),
  trip_id    uuid not null references public.trips(id) on delete cascade,
  token      text not null check (token ~ '^[0-9a-f]{32}$'),
  created_by uuid not null references public.profiles(id) on delete restrict,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  write_id   uuid not null default gen_random_uuid(),
  constraint trip_invites_token_unique unique (token)
);

comment on table public.trip_invites is
  'Per-trip secret join links. At most one active (revoked_at is null) invite per trip; the 128-bit hex token is the whole secret. Never client-synced; accessed only through RPCs.';

-- One active invite per trip; revoked invites are kept for audit.
create unique index trip_invites_active_uniq on public.trip_invites(trip_id)
  where revoked_at is null;
create index trip_invites_trip_id_idx on public.trip_invites(trip_id);
create index trip_invites_created_by_idx on public.trip_invites(created_by);

create trigger trg_trip_invites_sync_fields
  before insert or update on public.trip_invites
  for each row execute function public.set_sync_fields();

alter table public.trip_invites enable row level security;

-- Members may read their trip's invites (so any member can re-share or see
-- revocation state). All writes go through the RPCs below.
create policy trip_invites_select_member on public.trip_invites
  for select to authenticated using (private.is_trip_member(trip_id));

create or replace function public.get_or_create_trip_invite(
  p_trip_id uuid
)
returns public.trip_invites
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_invite public.trip_invites;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if exists (select 1 from public.trips t where t.id = p_trip_id and t.kind <> 'trip') then
    raise exception 'Group-trip RPC cannot target non-group containers' using errcode = '42501';
  end if;

  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.kind = 'trip' and t.deleted_at is null) then
    raise exception 'Trip not found or deleted' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(p_trip_id, v_actor) then
    raise exception 'Only trip members can share invite links' using errcode = '42501';
  end if;

  select * into v_invite
  from public.trip_invites
  where trip_id = p_trip_id and revoked_at is null;

  if found then
    return v_invite;
  end if;

  insert into public.trip_invites (trip_id, token, created_by)
  values (p_trip_id, encode(extensions.gen_random_bytes(16), 'hex'), v_actor)
  on conflict (trip_id) where revoked_at is null do nothing
  returning * into v_invite;

  -- Concurrent get_or_create: someone else won the insert race.
  if v_invite.id is null then
    select * into v_invite
    from public.trip_invites
    where trip_id = p_trip_id and revoked_at is null;
  end if;

  return v_invite;
end;
$$;

comment on function public.get_or_create_trip_invite(uuid) is
  'Returns the trip''s active invite link, minting one if none exists. Member-only; called when a member taps share.';

create or replace function public.revoke_trip_invite(
  p_trip_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not private.is_profile_trip_member(p_trip_id, v_actor) then
    raise exception 'Only trip members can revoke invite links' using errcode = '42501';
  end if;

  update public.trip_invites
  set revoked_at = clock_timestamp()
  where trip_id = p_trip_id and revoked_at is null;
end;
$$;

comment on function public.revoke_trip_invite(uuid) is
  'Turns off the trip''s active invite link. Idempotent; the next get_or_create_trip_invite mints a fresh token.';

create or replace function public.join_trip_with_invite(
  p_token text,
  p_person_id uuid default null
)
returns table (
  trip_id uuid,
  person_id uuid,
  trip_name text
)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := private.current_auth_email();
  v_token text := lower(trim(p_token));
  v_invite public.trip_invites;
  v_display_name text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' or v_email not like '%@%' then
    raise exception 'A verified email is required to join trips' using errcode = '22023';
  end if;

  select ti.* into v_invite
  from public.trip_invites ti
  join public.trips t on t.id = ti.trip_id
  where ti.token = v_token
    and ti.revoked_at is null
    and t.kind = 'trip'
    and t.deleted_at is null;

  if not found then
    raise exception 'This invite link is invalid or was turned off' using errcode = 'P0002';
  end if;

  select t.name into trip_name from public.trips t where t.id = v_invite.trip_id;

  select p.display_name into v_display_name
  from public.profiles p
  where p.id = v_actor;

  -- The deep link can be the first RPC after sign-in, before the app has
  -- ensured a profile row exists.
  insert into public.profiles (id, display_name)
  values (v_actor, left(coalesce(nullif(trim(v_display_name), ''), split_part(v_email, '@', 1)), 60))
  on conflict (id) do nothing;

  v_display_name := left(coalesce(nullif(trim(v_display_name), ''), split_part(v_email, '@', 1)), 60);

  -- Already claimed a person row in this trip (any email): opening the link
  -- is a rejoin — holding the secret link is equivalent to being re-added.
  update public.trip_people tp
  set removed_at = null
  where tp.trip_id = v_invite.trip_id
    and tp.user_id = v_actor
  returning tp.id into person_id;

  if person_id is not null then
    trip_id := v_invite.trip_id;
    return next;
    return;
  end if;

  -- Otherwise claim the pending row for this email (restoring it if removed —
  -- same rationale as above), or insert a fresh member. A pending row claimed
  -- by a different account never transfers.
  insert into public.trip_people (
    id, trip_id, user_id, email, display_name, invited_by, joined_at
  )
  values (
    coalesce(p_person_id, gen_random_uuid()),
    v_invite.trip_id,
    v_actor,
    v_email,
    v_display_name,
    v_invite.created_by,
    clock_timestamp()
  )
  on conflict on constraint trip_people_email_unique do update
    set user_id = v_actor,
        display_name = excluded.display_name,
        joined_at = coalesce(public.trip_people.joined_at, clock_timestamp()),
        removed_at = null
    where public.trip_people.user_id is null
  returning public.trip_people.id into person_id;

  if person_id is null then
    raise exception 'Person row for % is already claimed by another account', v_email
      using errcode = '42501';
  end if;

  trip_id := v_invite.trip_id;
  return next;
end;
$$;

comment on function public.join_trip_with_invite(text, uuid) is
  'Joins the current user to the trip behind an active invite token. Idempotent: existing members (including removed ones) are restored, a pending row matching the auth email is claimed, otherwise a new member row is created. Returns the trip so the app can sync and navigate.';

revoke execute on function public.get_or_create_trip_invite(uuid) from public, anon;
grant  execute on function public.get_or_create_trip_invite(uuid) to authenticated;
revoke execute on function public.revoke_trip_invite(uuid) from public, anon;
grant  execute on function public.revoke_trip_invite(uuid) to authenticated;
revoke execute on function public.join_trip_with_invite(text, uuid) from public, anon;
grant  execute on function public.join_trip_with_invite(text, uuid) to authenticated;


-- ============================================================================
