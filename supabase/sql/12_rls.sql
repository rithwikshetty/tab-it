-- 10. RLS policies
-- ============================================================================
-- All references to auth.uid() are wrapped in (select auth.uid()) so the auth
-- lookup is evaluated once per query, not once per row. Same semantics, much
-- faster at scale.

alter table public.profiles        enable row level security;
alter table public.trips           enable row level security;
alter table public.trip_people     enable row level security;
alter table public.categories      enable row level security;
alter table public.expenses          enable row level security;
alter table public.expense_payments  enable row level security;
alter table public.expense_splits    enable row level security;
alter table public.settlements     enable row level security;
alter table public.activity_log    enable row level security;
alter table public.push_devices    enable row level security;
alter table public.trip_mute_prefs enable row level security;

-- profiles: users can read their own profile and display fields for joined
-- people in shared trips. Column-level privileges deny shared reads of
-- activity_last_seen_at, the private Activity read cursor.
create policy profiles_select_self_or_shared_trip on public.profiles
  for select to authenticated using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.trip_people tp
      where tp.user_id = profiles.id
        and tp.joined_at is not null
        and private.is_trip_member(tp.trip_id)
    )
  );
create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy profiles_delete_self on public.profiles
  for delete to authenticated using (id = (select auth.uid()));

-- trips: only members can read/update/delete; you can create trips for yourself.
create policy trips_select_member on public.trips
  for select to authenticated using (private.is_trip_member(id));
-- Clients may only create real trips (kind='trip'). Hidden non-group containers are
-- created exclusively by resolve_or_create_non_group_container (SECURITY DEFINER).
create policy trips_insert_self_created on public.trips
  for insert to authenticated with check (created_by = (select auth.uid()) and kind = 'trip');
create policy trips_update_member on public.trips
  for update to authenticated
  using (private.is_trip_member(id) and kind = 'trip')
  with check (private.is_trip_member(id) and kind = 'trip');

-- trip_people: members can read the people in their trips. Inserts/claims and
-- removals go through server-owned paths so email matching and membership
-- changes stay server-side.
create policy trip_people_select_member on public.trip_people
  for select to authenticated using (private.is_trip_member(trip_id));

-- categories: defaults are globally readable; trip-scoped readable+writable by members.
create policy categories_select_default_or_member on public.categories
  for select to authenticated
  using (is_default or (trip_id is not null and private.is_trip_member(trip_id)));
create policy categories_insert_member_custom on public.categories
  for insert to authenticated
  with check (not is_default and trip_id is not null and private.is_trip_member(trip_id));
create policy categories_update_member_custom on public.categories
  for update to authenticated
  using  (not is_default and trip_id is not null and private.is_trip_member(trip_id))
  with check (not is_default and trip_id is not null and private.is_trip_member(trip_id));

-- expenses
create policy expenses_select_member on public.expenses
  for select to authenticated using (private.is_trip_member(trip_id));
create policy expenses_insert_member on public.expenses
  for insert to authenticated
  with check (
    private.is_trip_member(trip_id)
    and created_by = (select auth.uid())
    and (
      category_id is null
      or exists (
        select 1 from public.categories c
        where c.id = expenses.category_id
          and c.deleted_at is null
          and (c.is_default or c.trip_id = expenses.trip_id)
      )
    )
  );
create policy expenses_update_member on public.expenses
  for update to authenticated
  using (private.is_trip_member(trip_id))
  with check (
    private.is_trip_member(trip_id)
    -- _any: expenses authored by since-removed members stay editable.
    and private.is_profile_trip_member_any(trip_id, created_by)
    and (
      category_id is null
      or exists (
        select 1 from public.categories c
        where c.id = expenses.category_id
          and c.deleted_at is null
          and (c.is_default or c.trip_id = expenses.trip_id)
      )
    )
  );

-- expense_payments: visibility follows parent expense's trip membership.
create policy expense_payments_select_member on public.expense_payments
  for select to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_payments.expense_id and private.is_trip_member(e.trip_id)));
create policy expense_payments_insert_member on public.expense_payments
  for insert to authenticated
  with check (exists (
    select 1 from public.expenses e
    where e.id = expense_payments.expense_id
      and private.is_trip_member(e.trip_id)
      and private.is_trip_person(e.trip_id, expense_payments.trip_person_id)
  ));
create policy expense_payments_update_member on public.expense_payments
  for update to authenticated
  using  (exists (select 1 from public.expenses e where e.id = expense_payments.expense_id and private.is_trip_member(e.trip_id)))
  with check (exists (
    select 1 from public.expenses e
    where e.id = expense_payments.expense_id
      and private.is_trip_member(e.trip_id)
      and private.is_trip_person(e.trip_id, expense_payments.trip_person_id)
  ));
create policy expense_payments_delete_member on public.expense_payments
  for delete to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_payments.expense_id and private.is_trip_member(e.trip_id)));

-- expense_splits: visibility follows parent expense's trip membership.
create policy expense_splits_select_member on public.expense_splits
  for select to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)));
create policy expense_splits_insert_member on public.expense_splits
  for insert to authenticated
  with check (exists (
    select 1 from public.expenses e
    where e.id = expense_splits.expense_id
      and private.is_trip_member(e.trip_id)
      and private.is_trip_person(e.trip_id, expense_splits.trip_person_id)
  ));
create policy expense_splits_update_member on public.expense_splits
  for update to authenticated
  using  (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)))
  with check (exists (
    select 1 from public.expenses e
    where e.id = expense_splits.expense_id
      and private.is_trip_member(e.trip_id)
      and private.is_trip_person(e.trip_id, expense_splits.trip_person_id)
  ));
create policy expense_splits_delete_member on public.expense_splits
  for delete to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)));

-- settlements
create policy settlements_select_member on public.settlements
  for select to authenticated using (private.is_trip_member(trip_id));
create policy settlements_insert_member on public.settlements
  for insert to authenticated
  with check (
    private.is_trip_member(trip_id)
    and created_by = (select auth.uid())
    and private.is_trip_person(trip_id, from_person_id)
    and private.is_trip_person(trip_id, to_person_id)
  );
create policy settlements_update_member on public.settlements
  for update to authenticated
  using (private.is_trip_member(trip_id))
  with check (
    private.is_trip_member(trip_id)
    and private.is_trip_person(trip_id, from_person_id)
    and private.is_trip_person(trip_id, to_person_id)
    -- _any: settlements authored by since-removed members stay editable.
    and private.is_profile_trip_member_any(trip_id, created_by)
  );

-- activity_log: trigger-owned append-only stream. Clients may read events for
-- their trips, but may not forge events directly; domain triggers insert rows.
create policy activity_log_select_member on public.activity_log
  for select to authenticated using (private.is_trip_member(trip_id));

-- push_devices: self-only.
create policy push_devices_select_self on public.push_devices
  for select to authenticated using (user_id = (select auth.uid()));
create policy push_devices_insert_self on public.push_devices
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy push_devices_update_self on public.push_devices
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy push_devices_delete_self on public.push_devices
  for delete to authenticated using (user_id = (select auth.uid()));

-- trip_mute_prefs: self-only; insert also requires membership.
create policy trip_mute_prefs_select_self on public.trip_mute_prefs
  for select to authenticated using (user_id = (select auth.uid()));
create policy trip_mute_prefs_insert_self on public.trip_mute_prefs
  for insert to authenticated
  with check (user_id = (select auth.uid()) and private.is_trip_member(trip_id));
create policy trip_mute_prefs_update_self on public.trip_mute_prefs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and private.is_trip_member(trip_id));
create policy trip_mute_prefs_delete_self on public.trip_mute_prefs
  for delete to authenticated using (user_id = (select auth.uid()));


-- ============================================================================
