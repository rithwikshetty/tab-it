-- 16_rls_deny_paths.sql — RLS deny paths for categories, expenses,
-- settlements, trips, profiles, activity_log, push_devices, trip_mute_prefs
-- and the receipt storage policies, each next to a member allow path.
-- A refused UPDATE or DELETE affects zero rows; a refused INSERT raises 42501.

begin;
set search_path = extensions, public, pg_temp;

select plan(30);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000071', 'member71@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Member"}'),
  ('00000000-0000-0000-0000-000000000072', 'outsider72@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Outsider"}');

-- Member's trip, with a pending second person so a settlement has two parties.
insert into public.trips (id, name, created_by)
values ('71111111-1111-1111-1111-111111111111', 'Member Trip', '00000000-0000-0000-0000-000000000071');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values
  ('70000000-0000-0000-0000-000000000001', '71111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000071', 'member71@test.tab', 'Member',
   '00000000-0000-0000-0000-000000000071', now()),
  ('70000000-0000-0000-0000-000000000002', '71111111-1111-1111-1111-111111111111',
   null, 'pending71@test.tab', 'Pending',
   '00000000-0000-0000-0000-000000000071', null);

insert into public.categories (id, trip_id, name, icon)
values ('73000000-0000-0000-0000-000000000001', '71111111-1111-1111-1111-111111111111', 'Snacks', 'food');

insert into public.expenses (id, trip_id, amount, currency, description, expense_date, receipt_storage_path, created_by)
values ('72000000-0000-0000-0000-000000000001', '71111111-1111-1111-1111-111111111111',
        20, 'EUR', 'Member dinner', '2026-06-01',
        '71111111-1111-1111-1111-111111111111/72000000-0000-0000-0000-000000000001.jpg',
        '00000000-0000-0000-0000-000000000071');
insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
values ('72000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 20, 'exact');
insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
values ('72000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000002', 20, 'exact');

insert into public.settlements (id, trip_id, from_person_id, to_person_id, amount, currency, created_by)
values ('74000000-0000-0000-0000-000000000001', '71111111-1111-1111-1111-111111111111',
        '70000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000001',
        20, 'EUR', '00000000-0000-0000-0000-000000000071');

insert into public.activity_log (id, trip_id, actor_id, action, entity_type, entity_id)
values ('75000000-0000-0000-0000-000000000001', '71111111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000071', 'expense_created', 'expense',
        '72000000-0000-0000-0000-000000000001');

insert into public.push_devices (user_id, apns_token, device_name)
values
  ('00000000-0000-0000-0000-000000000071', 'token-member-71', 'Member iPhone'),
  ('00000000-0000-0000-0000-000000000072', 'token-outsider-72', 'Outsider iPhone');

insert into public.trip_mute_prefs (trip_id, user_id)
values ('71111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000071');

insert into storage.objects (bucket_id, name)
values ('receipts', '71111111-1111-1111-1111-111111111111/72000000-0000-0000-0000-000000000001.jpg');

-- ============================================================================
-- Outsider: reads come back empty, updates touch nothing, inserts raise.
-- ============================================================================
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000072","role":"authenticated"}';

-- categories
insert into _r select is(
  (select count(*)::int from public.categories where trip_id = '71111111-1111-1111-1111-111111111111'),
  0, 'non-member cannot read a trip''s custom categories');

insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon)
    values ('71111111-1111-1111-1111-111111111111', 'Planted', 'x')$$,
  '42501', null, 'non-member cannot insert a category into the trip');

with u as (
  update public.categories set name = 'Hijacked'
  where id = '73000000-0000-0000-0000-000000000001' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'non-member update of a category affects no rows');

-- expenses
insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = '71111111-1111-1111-1111-111111111111'),
  0, 'non-member cannot read the trip''s expenses');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, amount, currency, description, expense_date, created_by)
    values ('71111111-1111-1111-1111-111111111111', 5, 'EUR', 'Planted', '2026-06-02',
            '00000000-0000-0000-0000-000000000071')$$,
  '42501', null, 'non-member cannot insert an expense through REST');

with u as (
  update public.expenses
  set description = 'Hijacked', updated_at = '2026-06-03T00:00:00Z', write_id = gen_random_uuid()
  where id = '72000000-0000-0000-0000-000000000001' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'non-member update of an expense affects no rows');

-- settlements
insert into _r select is(
  (select count(*)::int from public.settlements where trip_id = '71111111-1111-1111-1111-111111111111'),
  0, 'non-member cannot read the trip''s settlements');

with u as (
  update public.settlements
  set note = 'Hijacked', updated_at = '2026-06-03T00:00:00Z', write_id = gen_random_uuid()
  where id = '74000000-0000-0000-0000-000000000001' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'non-member update of a settlement affects no rows');

-- trips
with u as (
  update public.trips
  set name = 'Hijacked', updated_at = '2026-06-03T00:00:00Z', write_id = gen_random_uuid()
  where id = '71111111-1111-1111-1111-111111111111' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'non-member rename of a trip affects no rows');

with u as (
  update public.trips
  set deleted_at = '2026-06-03T00:00:00Z', updated_at = '2026-06-03T00:00:00Z', write_id = gen_random_uuid()
  where id = '71111111-1111-1111-1111-111111111111' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'non-member soft-delete of a trip affects no rows');

-- profiles
insert into _r select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('00000000-0000-0000-0000-000000000079', 'Impostor')$$,
  '42501', null, 'user cannot insert a profile for another user');

with u as (
  update public.profiles set display_name = 'Hijacked'
  where id = '00000000-0000-0000-0000-000000000071' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'user cannot update another user''s profile');

-- activity_log
insert into _r select is(
  (select count(*)::int from public.activity_log where trip_id = '71111111-1111-1111-1111-111111111111'),
  0, 'non-member cannot read the trip''s activity');

-- push_devices
with u as (
  update public.push_devices set device_name = 'Hijacked'
  where user_id = '00000000-0000-0000-0000-000000000071' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'user cannot update another user''s push device');

insert into _r select throws_ok(
  $$update public.push_devices set user_id = '00000000-0000-0000-0000-000000000071'
    where apns_token = 'token-outsider-72'$$,
  '42501', null, 'user cannot hand their push device to another user');

-- trip_mute_prefs
insert into _r select throws_ok(
  $$insert into public.trip_mute_prefs (trip_id, user_id)
    values ('71111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000071')$$,
  '42501', null, 'user cannot insert a mute pref as another user');

with u as (
  update public.trip_mute_prefs set muted_at = now()
  where user_id = '00000000-0000-0000-0000-000000000071' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'user cannot update another user''s mute pref');

-- receipt storage
insert into _r select is(
  (select count(*)::int from storage.objects where bucket_id = 'receipts'
     and name like '71111111-1111-1111-1111-111111111111/%'),
  0, 'non-member cannot read the trip''s receipt objects');

insert into _r select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('receipts', '71111111-1111-1111-1111-111111111111/72000000-0000-0000-0000-000000000001.jpg')$$,
  '42501', null, 'non-member cannot write a receipt object for the trip');

with u as (
  update storage.objects set metadata = '{"planted":true}'::jsonb
  where bucket_id = 'receipts' and name like '71111111-1111-1111-1111-111111111111/%' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'non-member update of a receipt object affects no rows');

-- ============================================================================
-- Member: allow paths, and the activity log stays append-only even for them.
-- ============================================================================
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.categories where trip_id = '71111111-1111-1111-1111-111111111111'),
  1, 'member reads the trip''s custom category');

insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = '71111111-1111-1111-1111-111111111111'),
  1, 'member reads the trip''s expense');

insert into _r select is(
  (select count(*)::int from public.settlements where trip_id = '71111111-1111-1111-1111-111111111111'),
  1, 'member reads the trip''s settlement');

insert into _r select is(
  (select count(*)::int from public.activity_log where trip_id = '71111111-1111-1111-1111-111111111111'),
  1, 'member reads the trip''s activity');

with u as (
  update public.activity_log set action = 'trip_updated'
  where id = '75000000-0000-0000-0000-000000000001' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'member update of an activity row affects no rows');

with u as (
  delete from public.activity_log
  where id = '75000000-0000-0000-0000-000000000001' returning 1
)
insert into _r select is((select count(*)::int from u), 0, 'member delete of an activity row affects no rows');

insert into _r select throws_ok(
  $$update public.trip_mute_prefs set user_id = '00000000-0000-0000-0000-000000000072'
    where user_id = '00000000-0000-0000-0000-000000000071'$$,
  '23514', null, 'user cannot move their mute pref to a user outside the trip');

insert into _r select is(
  (select count(*)::int from storage.objects where bucket_id = 'receipts'
     and name = '71111111-1111-1111-1111-111111111111/72000000-0000-0000-0000-000000000001.jpg'),
  1, 'member reads the trip''s receipt object');

-- ============================================================================
-- Server view: nothing the refused writes targeted changed.
-- ============================================================================
reset role;

insert into _r select ok(
  (select name = 'Member Trip' and deleted_at is null
   from public.trips where id = '71111111-1111-1111-1111-111111111111'),
  'trip keeps its name and stays live');

insert into _r select ok(
  (select action = 'expense_created'
   from public.activity_log where id = '75000000-0000-0000-0000-000000000001'),
  'activity row is unchanged');

insert into _r select * from finish();
select line from _r;
rollback;
