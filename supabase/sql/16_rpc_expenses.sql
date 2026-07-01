-- ============================================================================
-- Client RPCs: expenses
-- ============================================================================

create or replace function public.create_expense_with_payments_and_splits(
    p_expense  jsonb,
    p_payments jsonb,
    p_splits   jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
    v_actor      uuid := auth.uid();
    v_expense_id uuid;
    v_trip_id    uuid;
    v_payment    jsonb;
    v_split      jsonb;
    v_write_id   uuid        := nullif(p_expense->>'write_id', '')::uuid;
    v_updated_at timestamptz := nullif(p_expense->>'updated_at', '')::timestamptz;
begin
    if v_actor is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    v_expense_id := coalesce((p_expense->>'id')::uuid, gen_random_uuid());
    v_trip_id    := (p_expense->>'trip_id')::uuid;

    if v_trip_id is null then
        raise exception 'trip_id is required' using errcode = '22023';
    end if;

    if not private.is_profile_trip_member(v_trip_id, v_actor) then
        raise exception 'Must be a trip member to write expenses' using errcode = '42501';
    end if;

    if not exists (select 1 from public.trips where id = v_trip_id and deleted_at is null) then
        raise exception 'Trip not found or deleted' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.expenses
        where id = v_expense_id
          and trip_id <> v_trip_id
    ) then
        raise exception 'Expense belongs to a different trip' using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.expenses
        where id = v_expense_id
          and trip_id = v_trip_id
          and deleted_at is not null
    ) then
        raise exception 'Cannot edit a deleted expense' using errcode = '23514';
    end if;

    insert into public.expenses (
        id, trip_id, amount, currency, category_id,
        description, expense_date, receipt_storage_path, payment_method,
        created_by, last_edited_by, updated_at, write_id
    )
    values (
        v_expense_id,
        v_trip_id,
        (p_expense->>'amount')::numeric(20, 8),
        p_expense->>'currency',
        nullif(p_expense->>'category_id', '')::uuid,
        p_expense->>'description',
        (p_expense->>'expense_date')::date,
        nullif(p_expense->>'receipt_storage_path', ''),
        coalesce(nullif(p_expense->>'payment_method', ''), 'card'),
        v_actor,
        case when nullif(p_expense->>'last_edited_by', '') is null then null else v_actor end,
        coalesce(v_updated_at, clock_timestamp()),
        coalesce(v_write_id, gen_random_uuid())
    )
    on conflict (id) do update set
        amount               = excluded.amount,
        currency             = excluded.currency,
        category_id          = excluded.category_id,
        description          = excluded.description,
        expense_date         = excluded.expense_date,
        receipt_storage_path = excluded.receipt_storage_path,
        payment_method       = excluded.payment_method,
        last_edited_by       = v_actor,
        updated_at           = excluded.updated_at,
        write_id             = excluded.write_id;

    -- LWW: when the expense update was skipped as stale (set_sync_fields kept
    -- the newer row), the ledgers must stay untouched as well.
    if v_write_id is not null and not exists (
        select 1 from public.expenses
        where id = v_expense_id and write_id = v_write_id
    ) then
        return v_expense_id;
    end if;

    delete from public.expense_payments where expense_id = v_expense_id;
    delete from public.expense_splits   where expense_id = v_expense_id;

    for v_payment in select * from jsonb_array_elements(p_payments)
    loop
        insert into public.expense_payments (
            expense_id, trip_person_id, amount_paid, payment_mode, updated_at, write_id
        )
        values (
            v_expense_id,
            (v_payment->>'trip_person_id')::uuid,
            (v_payment->>'amount_paid')::numeric(20, 8),
            v_payment->>'payment_mode',
            coalesce(nullif(v_payment->>'updated_at', '')::timestamptz, clock_timestamp()),
            coalesce(nullif(v_payment->>'write_id', '')::uuid, gen_random_uuid())
        );
    end loop;

    for v_split in select * from jsonb_array_elements(p_splits)
    loop
        insert into public.expense_splits (
            expense_id, trip_person_id, amount_owed, split_type, share_units, percentage, updated_at, write_id
        )
        values (
            v_expense_id,
            (v_split->>'trip_person_id')::uuid,
            (v_split->>'amount_owed')::numeric(20, 8),
            v_split->>'split_type',
            nullif(v_split->>'share_units', '')::numeric(20, 8),
            nullif(v_split->>'percentage', '')::numeric(20, 8),
            coalesce(nullif(v_split->>'updated_at', '')::timestamptz, clock_timestamp()),
            coalesce(nullif(v_split->>'write_id', '')::uuid, gen_random_uuid())
        );
    end loop;

    return v_expense_id;
end;
$$;

comment on function public.create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) is
    'Atomically upserts an expense and replaces its payments + splits. Required because the deferred payment-sum and split-sum constraints would fail on separate REST writes.';


-- ============================================================================
