-- 13_account_deletion.sql — delete_account_data purges sole-member trips,
-- anonymizes identity in shared trips and shared non-group signatures, ghosts
-- the profile, and leaves the auth.users row deletable. Clients must not be
-- able to call it.

begin;
set search_path = extensions, public, pg_temp;

select plan(18);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000051', 'dora@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Dora"}'),
  ('00000000-0000-0000-0000-000000000052', 'frank@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Frank"}');

-- Sole trip: only Dora ever claimed a membership.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000051","role":"authenticated"}';
select public.create_trip_with_self(
  '41111111-1111-1111-1111-111111111111',
  '40000000-0000-0000-0000-000000000001',
  'Dora Solo'
);
-- Shared trip: Dora creates, Frank is a claimed member.
select public.create_trip_with_self(
  '43333333-3333-3333-3333-333333333333',
  '40000000-0000-0000-0000-000000000002',
  'Shared Trip'
);
reset role;

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values ('40000000-0000-0000-0000-000000000003', '43333333-3333-3333-3333-333333333333',
        '00000000-0000-0000-0000-000000000052', 'frank@test.tab', 'Frank',
        '00000000-0000-0000-0000-000000000051', now());

-- Pending email-only person Dora pre-added to the shared trip: inviter's data, kept.
insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by)
values ('40000000-0000-0000-0000-000000000004', '43333333-3333-3333-3333-333333333333',
        null, 'pending@test.tab', 'Pending Pal',
        '00000000-0000-0000-0000-000000000051');

-- Expense with a receipt in the sole trip (must be hard-deleted, path returned).
insert into public.expenses (id, trip_id, amount, currency, description, expense_date, receipt_storage_path, created_by)
values ('42222222-0000-0000-0000-000000000001', '41111111-1111-1111-1111-111111111111',
        10, 'USD', 'Solo dinner', '2026-06-01',
        '41111111-1111-1111-1111-111111111111/42222222-0000-0000-0000-000000000001.jpg',
        '00000000-0000-0000-0000-000000000051');
insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
values ('42222222-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 10, 'exact');
insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
values ('42222222-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 10, 'exact');

-- Expense by Dora in the shared trip (group ledger, must survive).
insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
values ('42222222-0000-0000-0000-000000000002', '43333333-3333-3333-3333-333333333333',
        20, 'USD', 'Shared taxi', '2026-06-02',
        '00000000-0000-0000-0000-000000000051');
insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
values ('42222222-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 20, 'exact');
insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
values ('42222222-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003', 20, 'exact');

insert into public.push_devices (user_id, apns_token)
values ('00000000-0000-0000-0000-000000000051', 'tok-dora');
insert into public.trip_mute_prefs (trip_id, user_id)
values ('43333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000051');

-- Non-group container shared by Dora and Frank; Frank claims his row, so it
-- is not a sole-member trip.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000051","role":"authenticated"}';
create temp table _ng as
  select distinct trip_id
  from public.resolve_or_create_non_group_container('[{"email":"frank@test.tab","display_name":"Frank"}]'::jsonb);
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000052","role":"authenticated"}';
select count(*) from public.claim_trip_people_for_current_email();

insert into _r select is(
  (select member_signature from public.trips where id = (select trip_id from _ng)),
  'dora@test.tab|frank@test.tab',
  'before the purge the non-group signature lists Dora''s email');

-- ── Deny path: clients cannot call the purge directly.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000051","role":"authenticated"}';
insert into _r select throws_ok(
  $$select * from public.delete_account_data('00000000-0000-0000-0000-000000000051')$$,
  '42501', null, 'authenticated cannot execute delete_account_data');
reset role;

-- ── Allow path: service-side purge.
create temp table _paths as
  select * from public.delete_account_data('00000000-0000-0000-0000-000000000051');

insert into _r select results_eq(
  'select receipt_path from _paths',
  $$values ('41111111-1111-1111-1111-111111111111/42222222-0000-0000-0000-000000000001.jpg')$$,
  'purge returns the sole-trip receipt path for storage cleanup');

insert into _r select is(
  (select count(*)::int from public.trips where id = '41111111-1111-1111-1111-111111111111'),
  0, 'sole-member trip is hard-deleted');

insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = '41111111-1111-1111-1111-111111111111'),
  0, 'sole-member trip expenses are hard-deleted');

insert into _r select is(
  (select count(*)::int from public.trips where id = '43333333-3333-3333-3333-333333333333'),
  1, 'shared trip survives');

insert into _r select is(
  (select count(*)::int from public.expenses where id = '42222222-0000-0000-0000-000000000002'),
  1, 'shared-trip expense created by the deleted user survives');

insert into _r select is(
  (select email from public.trip_people where id = '40000000-0000-0000-0000-000000000002'),
  'deleted-40000000-0000-0000-0000-000000000002@account-deleted.invalid',
  'claimed person row email is scrubbed in the shared trip');

insert into _r select ok(
  (select user_id = '00000000-0000-0000-0000-000000000051' and joined_at is not null
   from public.trip_people where id = '40000000-0000-0000-0000-000000000002'),
  'claimed person row keeps ghost user link and join state');

insert into _r select is(
  (select email from public.trip_people where id = '40000000-0000-0000-0000-000000000003'),
  'frank@test.tab', 'other member person row is untouched');

insert into _r select is(
  (select email from public.trip_people where id = '40000000-0000-0000-0000-000000000004'),
  'pending@test.tab', 'pending email-only person row is untouched');

insert into _r select is(
  (select member_signature from public.trips where id = (select trip_id from _ng)),
  (select 'deleted-' || tp.id || '@account-deleted.invalid|frank@test.tab'
   from public.trip_people tp
   where tp.trip_id = (select trip_id from _ng)
     and tp.user_id = '00000000-0000-0000-0000-000000000051'),
  'non-group signature swaps Dora''s email for her scrubbed address, still sorted');

insert into _r select ok(
  (select display_name = 'Deleted user' and avatar_url is null and deleted_at is not null
   from public.profiles where id = '00000000-0000-0000-0000-000000000051'),
  'profile is ghosted: anonymized and stamped deleted');

insert into _r select is(
  (select count(*)::int from public.push_devices where user_id = '00000000-0000-0000-0000-000000000051'),
  0, 'push devices are deleted');

insert into _r select is(
  (select count(*)::int from public.trip_mute_prefs where user_id = '00000000-0000-0000-0000-000000000051'),
  0, 'mute prefs are deleted');

-- The edge function deletes the auth user afterwards: must work without FK fallout.
insert into _r select lives_ok(
  $$delete from auth.users where id = '00000000-0000-0000-0000-000000000051'$$,
  'auth user row can be deleted after the purge');

insert into _r select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-000000000051'),
  1, 'ghost profile outlives the auth user');

-- A new account with the old email gets its own container, not the old one.
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000053', 'dora@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"New Dora"}');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000053","role":"authenticated"}';

insert into _r select ok(
  (select bool_and(trip_id <> (select trip_id from _ng))
   from public.resolve_or_create_non_group_container('[{"email":"frank@test.tab","display_name":"Frank"}]'::jsonb)),
  'a new account with the deleted email does not match the old non-group container');

insert into _r select * from finish();
select line from _r;
rollback;
