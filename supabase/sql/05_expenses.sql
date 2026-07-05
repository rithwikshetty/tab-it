-- 6. expenses + expense_payments + expense_splits + touch_trip_last_activity trigger
-- ============================================================================

create table public.expenses (
  id                   uuid primary key default gen_random_uuid(),
  trip_id              uuid not null references public.trips(id) on delete restrict,
  amount               numeric(20, 8) not null check (amount > 0),
  currency             text not null check (char_length(currency) = 3 and currency = upper(currency)),
  category_id          uuid references public.categories(id) on delete set null,
  description          text not null check (char_length(trim(description)) > 0 and char_length(description) <= 200),
  expense_date         date not null,
  receipt_storage_path text check (receipt_storage_path is null or char_length(receipt_storage_path) <= 512),
  payment_method       text not null default 'card' check (payment_method in ('cash', 'card', 'bank_transfer')),
  created_by           uuid not null references public.profiles(id) on delete restrict,
  last_edited_by       uuid references public.profiles(id) on delete restrict,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  write_id             uuid not null default gen_random_uuid()
);

comment on table public.expenses is
  'Group expenses. Soft-delete via deleted_at. Payers live in expense_payments (multi-payer); participants live in expense_splits.';

create index expenses_trip_id_idx     on public.expenses(trip_id);
create index expenses_trip_active_idx on public.expenses(trip_id, expense_date desc) where deleted_at is null;
create index expenses_category_id_idx on public.expenses(category_id) where category_id is not null;
create index expenses_created_by_idx  on public.expenses(created_by);

create trigger trg_expenses_sync_fields
  before insert or update on public.expenses
  for each row execute function public.set_sync_fields();

create or replace function public.validate_expense_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'UPDATE' then
    if new.trip_id is distinct from old.trip_id then
      raise exception 'expenses.trip_id is immutable' using errcode = '42501';
    end if;

    if new.created_by is distinct from old.created_by then
      raise exception 'expenses.created_by is immutable' using errcode = '42501';
    end if;
  end if;

  if not exists (select 1 from public.trips where id = new.trip_id and deleted_at is null) then
    raise exception 'Expense trip must exist and be active' using errcode = '23514';
  end if;

  -- _any: the creator may have been removed from the trip since; their old
  -- expenses must stay editable and soft-deletable by remaining members.
  if not private.is_profile_trip_member_any(new.trip_id, new.created_by) then
    raise exception 'Expense creator must be a trip member' using errcode = '23514';
  end if;

  -- _any: a stale last_edited_by pointing at a since-removed member must not
  -- block later updates; the current actor is still gated by RLS.
  if new.last_edited_by is not null
     and not private.is_profile_trip_member_any(new.trip_id, new.last_edited_by) then
    raise exception 'Expense editor must be a trip member' using errcode = '23514';
  end if;

  if new.category_id is not null and not exists (
    select 1 from public.categories c
    where c.id = new.category_id
      and c.deleted_at is null
      and (c.is_default or c.trip_id = new.trip_id)
  ) then
    raise exception 'Expense category must be default or belong to the expense trip' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_expenses_validate
  before insert or update of trip_id, category_id, created_by, last_edited_by, deleted_at on public.expenses
  for each row execute function public.validate_expense_row();

create or replace function public.touch_trip_last_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_trip_id uuid;
begin
  v_trip_id := coalesce(new.trip_id, old.trip_id);
  if v_trip_id is not null then
    update public.trips set last_activity_at = clock_timestamp() where id = v_trip_id;
  end if;
  return coalesce(new, old);
end;
$$;

comment on function public.touch_trip_last_activity() is
  'Updates trips.last_activity_at when an expense or settlement is written. Used by TripStateDeriver.';

create trigger trg_expenses_touch_trip
  after insert or update or delete on public.expenses
  for each row execute function public.touch_trip_last_activity();
