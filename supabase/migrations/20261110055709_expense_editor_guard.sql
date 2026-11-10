-- Forward-only: replaces the body of public.validate_expense_row(). No table,
-- column, index, policy, trigger, grant or data changes. CREATE OR REPLACE
-- keeps the function's owner, SECURITY DEFINER mode and privileges.
--
-- A signed-in writer can only record themselves as expenses.last_edited_by:
-- an insert may leave it null or name auth.uid(), and an update that changes
-- it must set auth.uid(). Requests without a user (service role, maintenance)
-- are not limited. create_expense_with_payments_and_splits already writes
-- auth.uid(), and a write that re-sends the stored value is unaffected.

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

  -- A signed-in writer can only record themselves as the last editor.
  -- Requests without a user (service role, maintenance) are not limited.
  if auth.uid() is not null
     and new.last_edited_by is distinct from auth.uid()
     and (
       (tg_op = 'INSERT' and new.last_edited_by is not null)
       or (tg_op = 'UPDATE' and new.last_edited_by is distinct from old.last_edited_by)
     ) then
    raise exception 'expenses.last_edited_by must be the current user' using errcode = '42501';
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
