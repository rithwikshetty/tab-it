-- 02_constraints.sql — constraints for trip_people and ledger references.

begin;
set search_path = extensions, public, pg_temp;

select plan(28);
create temp table _r (line text);

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}'),
  ('00000000-0000-0000-0000-000000000003', 'carol@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Carol"}');

insert into public.trips (id, name, created_by)
values
  ('11111111-1111-1111-1111-111111111111', 'Lisbon', '00000000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', 'Solo',   '00000000-0000-0000-0000-000000000003');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values
  ('10000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'alice@test.tab', 'Alice', '00000000-0000-0000-0000-000000000001', now()),
  ('10000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002', 'bob@test.tab',   'Bob',   '00000000-0000-0000-0000-000000000001', now()),
  ('20000000-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000003', 'carol@test.tab', 'Carol', '00000000-0000-0000-0000-000000000003', now());

insert into _r select throws_ok(
  $$insert into public.trip_people (trip_id, email, display_name) values ('11111111-1111-1111-1111-111111111111', 'UPPER@test.tab', 'Upper')$$,
  '23514', null, 'trip_people.email must be normalized');

insert into _r select throws_ok(
  $$insert into public.trip_people (trip_id, email, display_name, joined_at) values ('11111111-1111-1111-1111-111111111111', 'pending@test.tab', 'Pending', now())$$,
  '23514', null, 'pending trip person cannot have joined_at without user_id');

insert into _r select throws_ok(
  $$insert into public.trip_people (trip_id, email, display_name) values ('11111111-1111-1111-1111-111111111111', 'alice@test.tab', 'Alice Duplicate')$$,
  '23505', null, 'duplicate person email per trip rejected');

insert into _r select throws_ok(
  $$insert into public.trip_people (trip_id, user_id, email, display_name, joined_at) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002', 'bob2@test.tab', 'Bob Duplicate', now())$$,
  '23505', null, 'duplicate joined user per trip rejected');

insert into _r select lives_ok(
  $$insert into public.trip_people (trip_id, email, display_name) values ('11111111-1111-1111-1111-111111111111', 'new@test.tab', 'New Person')$$,
  'pending trip person accepted');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, amount, currency, description, expense_date, created_by) values ('11111111-1111-1111-1111-111111111111', 0, 'EUR', 'zero', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'expense amount = 0 rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, amount, currency, description, expense_date, created_by) values ('11111111-1111-1111-1111-111111111111', 10, 'eur', 'lower currency', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'lowercase currency rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, amount, currency, description, expense_date, created_by) values ('11111111-1111-1111-1111-111111111111', 10, 'EUR', '', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'empty expense description rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, amount, currency, description, expense_date, payment_method, created_by) values ('11111111-1111-1111-1111-111111111111', 10, 'EUR', 'Bad payment method', '2026-05-01', 'cheque', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'invalid expense payment method rejected');

insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 10, 'EUR', 'Dinner', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 10, 'equal');
    insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 10, 'equal');
    set constraints all immediate; set constraints all deferred;$$,
  'valid one-person expense accepted');

insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
      values ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 1.001, 'KWD', 'Kuwaiti coffee', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
      values ('aaaaaaaa-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 1.001, 'equal');
    insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 1.001, 'equal');
    set constraints all immediate; set constraints all deferred;$$,
  'three-decimal currency amounts accepted');

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 1, 'equal')$$,
  '23514', null, 'payment person from another trip rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 1, 'equal')$$,
  '23514', null, 'split person from another trip rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', -1, 'equal')$$,
  '23514', null, 'negative split rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'lol')$$,
  '23514', null, 'invalid split type rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'shares')$$,
  '23514', null, 'shares split without share_units rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type, share_units)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'equal', 1)$$,
  '23514', null, 'non-shares split with share_units rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type, share_units)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'shares', 0)$$,
  '23514', null, 'zero share_units rejected');

insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
      values ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 30, 'GBP', 'Pints', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
      values ('aaaaaaaa-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 30, 'equal');
    insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type, share_units)
      values ('aaaaaaaa-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 20, 'shares', 1),
             ('aaaaaaaa-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 10, 'shares', 0.5);
    set constraints all immediate; set constraints all deferred;$$,
  'shares expense with fractional share_units accepted');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'percentage')$$,
  '23514', null, 'percentage split without percentage rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type, percentage)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'equal', 50)$$,
  '23514', null, 'non-percentage split with percentage rejected');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type, percentage)
      values ('aaaaaaaa-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'percentage', 101)$$,
  '23514', null, 'percentage above 100 rejected');

insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
      values ('aaaaaaaa-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 80, 'GBP', 'Taxi', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
      values ('aaaaaaaa-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 80, 'equal');
    insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type, percentage)
      values ('aaaaaaaa-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 60, 'percentage', 75),
             ('aaaaaaaa-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', 20, 'percentage', 25);
    set constraints all immediate; set constraints all deferred;$$,
  'percentage expense with percentages accepted');

insert into _r select throws_ok(
  $$insert into public.settlements (trip_id, from_person_id, to_person_id, amount, currency, created_by)
      values ('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 10, 'EUR', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'settlement from_person = to_person rejected');

insert into _r select throws_ok(
  $$insert into public.settlements (trip_id, from_person_id, to_person_id, amount, currency, created_by)
      values ('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 10, 'EUR', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'settlement person from another trip rejected');

insert into _r select lives_ok(
  $$insert into public.settlements (trip_id, from_person_id, to_person_id, amount, currency, created_by)
      values ('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 5, 'EUR', '00000000-0000-0000-0000-000000000001')$$,
  'valid settlement accepted');

insert into _r select throws_ok(
  $$insert into public.trip_mute_prefs (trip_id, user_id) values ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'mute pref user must be a member of the trip');

insert into _r select lives_ok(
  $$insert into public.trip_mute_prefs (trip_id, user_id) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001')$$,
  'mute pref for joined user accepted');

insert into _r select * from finish();
select line from _r;
rollback;
