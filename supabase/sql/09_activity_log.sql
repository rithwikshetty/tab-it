-- 8. activity_log (append-only)
-- ============================================================================

create table public.activity_log (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references public.trips(id) on delete cascade,
  actor_id      uuid not null references public.profiles(id) on delete restrict,
  action        text not null check (action in (
    'expense_created', 'expense_updated', 'expense_deleted',
    'settlement_created', 'settlement_updated', 'settlement_deleted',
    'member_joined', 'member_left',
    'trip_created', 'trip_updated'
  )),
  entity_type   text not null check (entity_type in ('expense', 'settlement', 'trip', 'member')),
  entity_id     uuid not null,
  timestamp     timestamptz not null default now(),
  snapshot_json jsonb
);

comment on table public.activity_log is
  'Append-only audit trail written by domain triggers. No client INSERT/UPDATE/DELETE allowed via RLS.';

create index activity_log_trip_id_timestamp_idx on public.activity_log(trip_id, timestamp desc);
create index activity_log_actor_id_idx          on public.activity_log(actor_id);
create index activity_log_entity_idx            on public.activity_log(entity_type, entity_id);


-- ----------------------------------------------------------------------------
-- Event sourcing: AFTER triggers populate activity_log as the authenticated
-- actor. One row per meaningful event, feeding both the in-app Activity feed
-- and the push channel. See docs/adr/0002-notification-architecture.md.
--
-- Idempotent against offline re-syncs: UPDATE events fire only when a
-- user-visible column actually changes (IS DISTINCT FROM), so a no-op re-upsert
-- never produces a duplicate notification. Service-role/system writes have a
-- null auth.uid() and are skipped (no actor = nothing to notify).
-- ----------------------------------------------------------------------------

create or replace function private.profile_display_name(p_id uuid)
returns text language sql security definer stable set search_path = public, private as $$
  select coalesce(nullif(trim(display_name), ''), 'Someone') from public.profiles where id = p_id;
$$;

create or replace function private.trip_name(p_id uuid)
returns text language sql security definer stable set search_path = public, private as $$
  select case when kind = 'non_group' then 'Non-group' else name end
  from public.trips
  where id = p_id;
$$;

create or replace function private.person_display_name(p_id uuid)
returns text language sql security definer stable set search_path = public, private as $$
  select coalesce(nullif(trim(display_name), ''), 'Someone') from public.trip_people where id = p_id;
$$;

-- Compact money string for snapshot rendering/push text (client reformats via MoneyFormatter).
create or replace function private.money_text(p_amount numeric)
returns text language sql immutable set search_path = public, private as $$
  select trim(to_char(p_amount, 'FM999999999990.00'));
$$;

create or replace function public.log_expense_activity()
returns trigger language plpgsql security definer set search_path = public, private as $$
declare
  v_actor uuid := auth.uid();
  v_action text;
begin
  if v_actor is null then return coalesce(new, old); end if;

  if tg_op = 'INSERT' then
    v_action := 'expense_created';
  else
    if old.deleted_at is null and new.deleted_at is not null then
      v_action := 'expense_deleted';
    elsif old.deleted_at is not null and new.deleted_at is null then
      v_action := 'expense_created';
    elsif new.deleted_at is null and (
         old.amount         is distinct from new.amount
      or old.currency       is distinct from new.currency
      or old.category_id    is distinct from new.category_id
      or old.description    is distinct from new.description
      or old.expense_date   is distinct from new.expense_date
      or old.payment_method is distinct from new.payment_method
    ) then
      v_action := 'expense_updated';
    else
      return new;
    end if;
  end if;

  insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
  values (
    new.trip_id, v_actor, v_action, 'expense', new.id,
    jsonb_build_object(
      'actor_name',  private.profile_display_name(v_actor),
      'trip_name',   private.trip_name(new.trip_id),
      'description', new.description,
      'amount',      private.money_text(new.amount),
      'currency',    new.currency
    )
  );
  return new;
end;
$$;

create or replace function public.log_settlement_activity()
returns trigger language plpgsql security definer set search_path = public, private as $$
declare
  v_actor uuid := auth.uid();
  v_action text;
begin
  if v_actor is null then return coalesce(new, old); end if;

  if tg_op = 'INSERT' then
    v_action := 'settlement_created';
  else
    if old.deleted_at is null and new.deleted_at is not null then
      v_action := 'settlement_deleted';
    elsif old.deleted_at is not null and new.deleted_at is null then
      v_action := 'settlement_created';
    elsif new.deleted_at is null and (
         old.amount         is distinct from new.amount
      or old.currency       is distinct from new.currency
      or old.from_person_id is distinct from new.from_person_id
      or old.to_person_id   is distinct from new.to_person_id
      or old.note           is distinct from new.note
      or old.settled_at     is distinct from new.settled_at
    ) then
      v_action := 'settlement_updated';
    else
      return new;
    end if;
  end if;

  insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
  values (
    new.trip_id, v_actor, v_action, 'settlement', new.id,
    jsonb_build_object(
      'actor_name', private.profile_display_name(v_actor),
      'trip_name',  private.trip_name(new.trip_id),
      'from_name',  private.person_display_name(new.from_person_id),
      'to_name',    private.person_display_name(new.to_person_id),
      'amount',     private.money_text(new.amount),
      'currency',   new.currency
    )
  );
  return new;
end;
$$;

create or replace function public.log_membership_activity()
returns trigger language plpgsql security definer set search_path = public, private as $$
declare
  v_actor uuid := auth.uid();
  v_trip_id uuid := coalesce(new.trip_id, old.trip_id);
begin
  if v_actor is null then return coalesce(new, old); end if;
  if exists (select 1 from public.trips t where t.id = v_trip_id and t.kind = 'non_group') then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    -- Skip the creator adding themselves at trip creation (invited_by = user_id):
    -- it notifies no one and only clutters the audit trail.
    if new.invited_by is not null and new.invited_by is not distinct from new.user_id then
      return new;
    end if;
    insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
    values (
      new.trip_id, v_actor, 'member_joined', 'member', new.id,
      jsonb_build_object(
        'actor_name',  private.profile_display_name(v_actor),
        'trip_name',   private.trip_name(new.trip_id),
        'member_name', new.display_name
      )
    );
    return new;
  elsif tg_op = 'UPDATE' then
    -- Only removed_at transitions are membership events. Other updates —
    -- claims (user_id/joined_at), email edits, profile-rename display_name
    -- sync — stay silent, matching the pre-soft-removal behavior where
    -- member_joined fired once at insert.
    if old.removed_at is null and new.removed_at is not null then
      insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
      values (
        new.trip_id, v_actor, 'member_left', 'member', new.id,
        jsonb_build_object(
          'actor_name',  private.profile_display_name(v_actor),
          'trip_name',   private.trip_name(new.trip_id),
          'member_name', new.display_name
        )
      );
    elsif old.removed_at is not null and new.removed_at is null then
      insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
      values (
        new.trip_id, v_actor, 'member_joined', 'member', new.id,
        jsonb_build_object(
          'actor_name',  private.profile_display_name(v_actor),
          'trip_name',   private.trip_name(new.trip_id),
          'member_name', new.display_name
        )
      );
    end if;
    return new;
  else
    insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
    values (
      old.trip_id, v_actor, 'member_left', 'member', old.id,
      jsonb_build_object(
        'actor_name',  private.profile_display_name(v_actor),
        'trip_name',   private.trip_name(old.trip_id),
        'member_name', old.display_name
      )
    );
    return old;
  end if;
end;
$$;

create or replace function public.log_trip_activity()
returns trigger language plpgsql security definer set search_path = public, private as $$
declare
  v_actor uuid := auth.uid();
  v_action text;
begin
  if v_actor is null then return coalesce(new, old); end if;
  if new.kind = 'non_group' then return new; end if;

  if tg_op = 'INSERT' then
    v_action := 'trip_created';
  elsif old.name is distinct from new.name and new.deleted_at is null then
    v_action := 'trip_updated';
  else
    return new;
  end if;

  insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
  values (
    new.id, v_actor, v_action, 'trip', new.id,
    jsonb_build_object(
      'actor_name', private.profile_display_name(v_actor),
      'trip_name',  new.name
    )
  );
  return new;
end;
$$;

create trigger trg_expenses_activity
  after insert or update on public.expenses
  for each row execute function public.log_expense_activity();

create trigger trg_settlements_activity
  after insert or update on public.settlements
  for each row execute function public.log_settlement_activity();

create trigger trg_trip_people_activity
  after insert or update or delete on public.trip_people
  for each row execute function public.log_membership_activity();

create trigger trg_trips_activity
  after insert or update on public.trips
  for each row execute function public.log_trip_activity();


-- ============================================================================
