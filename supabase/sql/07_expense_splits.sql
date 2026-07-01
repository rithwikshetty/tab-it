-- ============================================================================
-- Expense split ledger
-- ============================================================================

create table public.expense_splits (
  expense_id     uuid not null references public.expenses(id) on delete cascade,
  trip_person_id uuid not null references public.trip_people(id) on delete restrict,
  amount_owed    numeric(20, 8) not null check (amount_owed >= 0),
  split_type     text not null check (split_type in ('equal', 'exact', 'percentage', 'shares', 'adjustment')),
  share_units    numeric(20, 8) check (share_units > 0),
  percentage     numeric(20, 8) check (percentage > 0 and percentage <= 100),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  write_id       uuid not null default gen_random_uuid(),
  primary key (expense_id, trip_person_id),
  constraint expense_splits_share_units_match_type
    check ((split_type = 'shares') = (share_units is not null)),
  constraint expense_splits_percentage_match_type
    check ((split_type = 'percentage') = (percentage is not null))
);

comment on column public.expense_splits.share_units is
  'Share weight the participant carries when split_type = shares (0.5 = half share). Null for every other split type.';

comment on column public.expense_splits.percentage is
  'Percentage of the total (0-100) when split_type = percentage. Null for every other split type.';

comment on table public.expense_splits is
  'Per-participant share of an expense. Cascade-deletes if the parent expense is hard-deleted.';

create index expense_splits_trip_person_id_idx on public.expense_splits(trip_person_id);

create trigger trg_expense_splits_sync_fields
  before insert or update on public.expense_splits
  for each row execute function public.set_sync_fields();

create or replace function public.validate_expense_split_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_trip_id uuid;
  v_deleted_at timestamptz;
begin
  select trip_id, deleted_at
  into v_trip_id, v_deleted_at
  from public.expenses
  where id = new.expense_id;

  if v_trip_id is null then
    raise exception 'Expense split parent expense must exist' using errcode = '23514';
  end if;

  if v_deleted_at is not null then
    raise exception 'Cannot write splits for a deleted expense' using errcode = '23514';
  end if;

  if not private.is_trip_person(v_trip_id, new.trip_person_id) then
    raise exception 'Expense split person must belong to the expense trip' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_expense_splits_validate
  before insert or update of expense_id, trip_person_id on public.expense_splits
  for each row execute function public.validate_expense_split_row();

create or replace function public.validate_expense_split_total(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(20, 8);
  v_deleted_at timestamptz;
  v_split_count int;
  v_split_total numeric(20, 8);
begin
  select amount, deleted_at
  into v_amount, v_deleted_at
  from public.expenses
  where id = p_expense_id;

  if v_amount is null or v_deleted_at is not null then
    return;
  end if;

  select count(*)::int, coalesce(sum(amount_owed), 0)::numeric(20, 8)
  into v_split_count, v_split_total
  from public.expense_splits
  where expense_id = p_expense_id;

  if v_split_count = 0 then
    raise exception 'Expense % must have at least one split', p_expense_id using errcode = '23514';
  end if;

  if v_split_total <> v_amount then
    raise exception 'Expense % split total % does not equal amount %', p_expense_id, v_split_total, v_amount
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.validate_expense_split_total_from_expense_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.validate_expense_split_total(coalesce(new.id, old.id));
  return coalesce(new, old);
end;
$$;

create or replace function public.validate_expense_split_total_from_split_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.validate_expense_split_total(coalesce(new.expense_id, old.expense_id));
  if tg_op = 'UPDATE'
     and old.expense_id is not null
     and new.expense_id is not null
     and old.expense_id <> new.expense_id then
    perform public.validate_expense_split_total(old.expense_id);
  end if;

  return coalesce(new, old);
end;
$$;

create constraint trigger trg_expenses_split_total
  after insert or update of amount, deleted_at on public.expenses
  deferrable initially deferred
  for each row execute function public.validate_expense_split_total_from_expense_trigger();

create constraint trigger trg_expense_splits_total
  after insert or update or delete on public.expense_splits
  deferrable initially deferred
  for each row execute function public.validate_expense_split_total_from_split_trigger();


-- ============================================================================
