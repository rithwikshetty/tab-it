-- 9. push_devices + trip_mute_prefs
-- ============================================================================

create table public.push_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  apns_token   text not null check (char_length(apns_token) > 0 and char_length(apns_token) <= 1024),
  device_name  text check (device_name is null or char_length(device_name) <= 100),
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  write_id     uuid not null default gen_random_uuid(),
  constraint push_devices_user_token_uniq unique (user_id, apns_token)
);

comment on table public.push_devices is 'APNs device tokens per user. One row per (user, device).';

create index push_devices_user_id_idx on public.push_devices(user_id);

create trigger trg_push_devices_sync_fields
  before insert or update on public.push_devices
  for each row execute function public.set_sync_fields();

-- Registration goes through an RPC (not a plain upsert) so the server can
-- release the token from any other account first. On a shared device,
-- sign-out + sign-in with a second account would otherwise leave both users'
-- rows for one physical device, and APNs would deliver both accounts' pushes.
create or replace function public.register_push_device(
  p_apns_token  text,
  p_device_name text default null
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_apns_token is null or char_length(p_apns_token) = 0 or char_length(p_apns_token) > 1024 then
    raise exception 'Invalid APNs token' using errcode = '23514';
  end if;

  delete from public.push_devices
  where apns_token = p_apns_token and user_id <> v_user;

  insert into public.push_devices (user_id, apns_token, device_name, last_seen_at)
  values (v_user, p_apns_token, left(p_device_name, 100), now())
  on conflict (user_id, apns_token)
  do update set device_name = excluded.device_name, last_seen_at = now();
end;
$$;

comment on function public.register_push_device(text, text) is
  'Upserts the caller''s APNs device token and releases it from any other account (shared-device sign-out/sign-in).';

revoke execute on function public.register_push_device(text, text) from public, anon;
grant execute on function public.register_push_device(text, text) to authenticated;

create table public.trip_mute_prefs (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  muted_at   timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  write_id   uuid not null default gen_random_uuid(),
  primary key (trip_id, user_id)
);

comment on table public.trip_mute_prefs is 'Per-user, per-trip mute. Row presence = muted; absence = unmuted.';

create index trip_mute_prefs_user_id_idx on public.trip_mute_prefs(user_id);

create trigger trg_trip_mute_prefs_sync_fields
  before insert or update on public.trip_mute_prefs
  for each row execute function public.set_sync_fields();

create or replace function public.validate_trip_mute_pref_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_profile_trip_member(new.trip_id, new.user_id) then
    raise exception 'Trip mute preference user must be a trip member' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_trip_mute_prefs_validate
  before insert or update of trip_id, user_id on public.trip_mute_prefs
  for each row execute function public.validate_trip_mute_pref_row();
