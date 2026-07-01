-- 3. profiles
-- ============================================================================

-- No FK to auth.users: account deletion removes the auth user but keeps an
-- anonymized "ghost" profile so shared-trip ledger rows (which restrict-reference
-- profiles) stay intact. Rows are created by trg_on_auth_user_created.
create table public.profiles (
  id           uuid primary key,
  display_name text not null check (
    char_length(trim(display_name)) > 0 and char_length(display_name) <= 60
  ),
  avatar_url   text check (avatar_url is null or char_length(avatar_url) <= 2048),
  activity_last_seen_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  write_id     uuid not null default gen_random_uuid()
);

comment on column public.profiles.deleted_at is
  'Set when the account is deleted. The row remains as an anonymized ghost so shared-trip ledger references stay valid; the auth.users row is gone.';

comment on column public.profiles.activity_last_seen_at is
  'Per-user read cursor for the Activity feed. Unread = activity_log rows newer than this. Advanced by mark_activity_seen().';

comment on table public.profiles is
  'Per-user profile data. activity_last_seen_at is a private read cursor protected by column privileges; shared display fields are exposed through visible_profiles.';

create trigger trg_profiles_sync_fields
  before insert or update on public.profiles
  for each row execute function public.set_sync_fields();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'given_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(coalesce(new.email, 'user'), '@', 1)
    )::text, 60)
  );
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.ensure_current_profile(
  p_display_name text default null,
  p_avatar_url text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_display_name text := nullif(trim(p_display_name), '');
  v_profile public.profiles;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if v_display_name is null then
    select coalesce(
      nullif(trim(raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(raw_user_meta_data ->> 'given_name'), ''),
      nullif(trim(raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(raw_user_meta_data ->> 'name'), ''),
      split_part(coalesce(email, 'user'), '@', 1)
    )
    into v_display_name
    from auth.users
    where id = v_actor;
  end if;

  v_display_name := left(coalesce(nullif(trim(v_display_name), ''), 'user'), 60);

  insert into public.profiles (id, display_name, avatar_url)
  values (v_actor, v_display_name, p_avatar_url)
  on conflict (id) do update
    set display_name = excluded.display_name,
        avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url)
  returning * into v_profile;

  return v_profile;
end;
$$;

-- Keeps trip ledger labels in step with the profile. trip_people.display_name
-- is copied from the profile once, at claim time; without this trigger, a user
-- who sets their name after signing in (magic-link signups start as an email
-- prefix) stays stale in every other member's app forever. set_sync_fields on
-- trip_people stamps fresh updated_at/write_id, so client LWW pulls apply it.
create or replace function public.sync_profile_name_to_trip_people()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.trip_people tp
  set display_name = left(trim(new.display_name), 60)
  where tp.user_id = new.id
    and tp.display_name is distinct from left(trim(new.display_name), 60);
  return new;
end;
$$;

create trigger trg_profiles_name_to_trip_people
  after update of display_name on public.profiles
  for each row
  when (
    new.deleted_at is null
    and nullif(trim(new.display_name), '') is not null
    and new.display_name is distinct from old.display_name
  )
  execute function public.sync_profile_name_to_trip_people();

-- Advances the caller's Activity read cursor. Monotonic (never moves backwards)
-- so a stale write from another device can't resurrect already-seen unread state.
-- Bumps write_id (via set_sync_fields) so the next pull carries the new cursor.
create or replace function public.mark_activity_seen()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_seen timestamptz;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set activity_last_seen_at = greatest(coalesce(activity_last_seen_at, '-infinity'::timestamptz), clock_timestamp())
  where id = v_actor
  returning activity_last_seen_at into v_seen;

  return v_seen;
end;
$$;

comment on function public.mark_activity_seen() is
  'Advances profiles.activity_last_seen_at to now for the caller. Called when the Activity tab is opened.';


-- ============================================================================
