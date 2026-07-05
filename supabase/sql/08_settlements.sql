-- 7. settlements
-- ============================================================================

create table public.settlements (
  id             uuid primary key default gen_random_uuid(),
  trip_id        uuid not null references public.trips(id) on delete restrict,
  from_person_id uuid not null references public.trip_people(id) on delete restrict,
  to_person_id   uuid not null references public.trip_people(id) on delete restrict,
  amount         numeric(20, 8) not null check (amount > 0),
  currency       text not null check (char_length(currency) = 3 and currency = upper(currency)),
  note           text check (note is null or char_length(note) <= 200),
  settled_at     timestamptz not null default now(),
  created_by     uuid not null references public.profiles(id) on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  write_id       uuid not null default gen_random_uuid(),
  constraint settlements_distinct_parties check (from_person_id <> to_person_id)
);

comment on table public.settlements is
  'Pairwise payments outside the app. Subtracted from balances by BalanceEngine.';

create index settlements_trip_id_idx     on public.settlements(trip_id);
create index settlements_trip_active_idx on public.settlements(trip_id, settled_at desc) where deleted_at is null;
create index settlements_from_person_id_idx on public.settlements(from_person_id);
create index settlements_to_person_id_idx   on public.settlements(to_person_id);
create index settlements_created_by_idx  on public.settlements(created_by);

create trigger trg_settlements_sync_fields
  before insert or update on public.settlements
  for each row execute function public.set_sync_fields();

create or replace function public.validate_settlement_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'UPDATE' then
    if new.trip_id is distinct from old.trip_id then
      raise exception 'settlements.trip_id is immutable' using errcode = '42501';
    end if;

    if new.created_by is distinct from old.created_by then
      raise exception 'settlements.created_by is immutable' using errcode = '42501';
    end if;
  end if;

  if not exists (select 1 from public.trips where id = new.trip_id and deleted_at is null) then
    raise exception 'Settlement trip must exist and be active' using errcode = '23514';
  end if;

  if not private.is_trip_person(new.trip_id, new.from_person_id) then
    raise exception 'Settlement from_person must belong to the trip' using errcode = '23514';
  end if;

  if not private.is_trip_person(new.trip_id, new.to_person_id) then
    raise exception 'Settlement to_person must belong to the trip' using errcode = '23514';
  end if;

  -- _any: the creator may have been removed from the trip since; their old
  -- settlements must stay editable and soft-deletable by remaining members.
  if not private.is_profile_trip_member_any(new.trip_id, new.created_by) then
    raise exception 'Settlement creator must be a trip member' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_settlements_validate
  before insert or update of trip_id, from_person_id, to_person_id, created_by, deleted_at on public.settlements
  for each row execute function public.validate_settlement_row();

create trigger trg_settlements_touch_trip
  after insert or update or delete on public.settlements
  for each row execute function public.touch_trip_last_activity();


-- ============================================================================
