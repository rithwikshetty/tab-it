-- 14. Push notification fan-out (activity_log -> edge function -> APNs)
-- ============================================================================
-- The in-app Activity feed works without any of this (it reads activity_log via
-- sync). This file wires the *push* channel: an AFTER INSERT trigger on
-- activity_log hands the new event to the `send-push` edge function over pg_net,
-- which resolves recipients (members - actor - muters), looks up their APNs
-- tokens, and sends. See docs/adr/0002-notification-architecture.md.
--
-- Config (function URL + shared secret) lives in private.app_config, seeded
-- out-of-band and NEVER committed. If unset, the trigger no-ops, so the app
-- still works fully without push configured.

create extension if not exists pg_net;

create table if not exists private.app_config (
  key   text primary key,
  value text not null
);

comment on table private.app_config is
  'Out-of-band runtime config (e.g. push webhook url + secret). Not exposed via PostgREST. Seed values manually; never commit them.';

create or replace function private.config(p_key text)
returns text
language sql
security definer
stable
set search_path = private
as $$
  select value from private.app_config where key = p_key;
$$;

-- Unread Activity count for one user: events on their joined trips, not their
-- own, newer than their read cursor, excluding muted trips and anything that
-- predates them joining the trip (a member claimed after months of activity
-- must not start at badge 100). Used by the edge function to stamp aps.badge
-- so the app-icon badge is correct with the app closed.
create or replace function public.unread_activity_count(p_user uuid)
returns integer
language sql
security definer
stable
set search_path = public, private
as $$
  select count(*)::int
  from public.activity_log a
  join public.profiles p on p.id = p_user
  where a.actor_id <> p_user
    and a.timestamp > coalesce(p.activity_last_seen_at, '-infinity'::timestamptz)
    and exists (
      select 1 from public.trip_people tp
      where tp.trip_id = a.trip_id
        and tp.user_id = p_user
        and tp.joined_at is not null
        and tp.removed_at is null
        and a.timestamp >= tp.joined_at
    )
    and not exists (
      select 1 from public.trip_mute_prefs m
      where m.trip_id = a.trip_id and m.user_id = p_user
    );
$$;

comment on function public.unread_activity_count(uuid) is
  'Count of unread Activity events for a user (excludes own actions and muted trips). For the push badge.';

-- One round-trip for the edge function: every device that should receive a push
-- for an activity (members - actor - muters), with that recipient's badge count.
create or replace function public.push_targets_for_activity(p_activity_id uuid)
returns table (user_id uuid, apns_token text, push_device_id uuid, badge integer)
language sql
security definer
stable
set search_path = public, private
as $$
  select pd.user_id, pd.apns_token, pd.id, public.unread_activity_count(pd.user_id)
  from public.activity_log a
  join public.trip_people tp
    on tp.trip_id = a.trip_id
   and tp.user_id is not null
   and tp.user_id <> a.actor_id
   and tp.joined_at is not null
   and tp.removed_at is null
  join public.push_devices pd on pd.user_id = tp.user_id
  where a.id = p_activity_id
    and not exists (
      select 1 from public.trip_mute_prefs m
      where m.trip_id = a.trip_id and m.user_id = tp.user_id
    );
$$;

comment on function public.push_targets_for_activity(uuid) is
  'Recipient devices + badge for an activity event. Called by the send-push edge function (service role).';

create or replace function public.notify_activity_push()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_url    text := private.config('push_webhook_url');
  v_secret text := private.config('push_webhook_secret');
begin
  if v_url is null then
    return new;  -- push not configured; in-app Activity still works
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',    'application/json',
      'x-webhook-secret', coalesce(v_secret, '')
    ),
    body    := jsonb_build_object(
      'activity_id', new.id,
      'trip_id',     new.trip_id,
      'actor_id',    new.actor_id,
      'action',      new.action,
      'entity_type', new.entity_type,
      'entity_id',   new.entity_id,
      'snapshot',    new.snapshot_json
    )
  );
  return new;
end;
$$;

create trigger trg_activity_notify_push
  after insert on public.activity_log
  for each row execute function public.notify_activity_push();

-- Lock down: these are internal. The edge function calls
-- push_targets_for_activity with the service-role key, which still needs
-- explicit EXECUTE even though it bypasses RLS.
revoke execute on function private.config(text)              from public, anon, authenticated;
revoke execute on function public.notify_activity_push()     from public, anon, authenticated;
revoke execute on function public.unread_activity_count(uuid) from public, anon, authenticated;
revoke execute on function public.push_targets_for_activity(uuid) from public, anon, authenticated;
grant execute on function public.push_targets_for_activity(uuid) to service_role;
