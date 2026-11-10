-- 17_expense_editor_guard.sql — a signed-in writer can only record themselves
-- as expenses.last_edited_by. Re-sending the stored value, the transactional
-- RPC, and requests without a user keep working.

begin;
set search_path = extensions, public, pg_temp;

select plan(9);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000081', 'ana81@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Ana"}'),
  ('00000000-0000-0000-0000-000000000082', 'ben82@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Ben"}');

insert into public.trips (id, name, created_by)
values ('81111111-1111-1111-1111-111111111111', 'Editor Trip', '00000000-0000-0000-0000-000000000081');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values
  ('80000000-0000-0000-0000-000000000001', '81111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000081', 'ana81@test.tab', 'Ana',
   '00000000-0000-0000-0000-000000000081', now()),
  ('80000000-0000-0000-0000-000000000002', '81111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000082', 'ben82@test.tab', 'Ben',
   '00000000-0000-0000-0000-000000000081', now());

-- Ana creates the expense through the RPC; it has no last editor yet.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000081","role":"authenticated"}';
select public.create_expense_with_payments_and_splits(
  '{"id":"82000000-0000-0000-0000-000000000001","trip_id":"81111111-1111-1111-1111-111111111111","amount":"30","currency":"EUR","description":"Taxi","expense_date":"2026-06-01","payment_method":"card","updated_at":"2026-06-01T10:00:00Z","write_id":"82aaaaaa-0000-0000-0000-000000000001"}'::jsonb,
  '[{"trip_person_id":"80000000-0000-0000-0000-000000000001","amount_paid":"30","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"80000000-0000-0000-0000-000000000002","amount_owed":"30","split_type":"equal"}]'::jsonb
);

-- ── Ben (a member) edits the row directly.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000082","role":"authenticated"}';

insert into _r select throws_ok(
  $$update public.expenses
    set description = 'Forged', last_edited_by = '00000000-0000-0000-0000-000000000081',
        updated_at = '2026-06-02T10:00:00Z', write_id = '82aaaaaa-0000-0000-0000-000000000002'
    where id = '82000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'a member cannot record another member as last editor');

insert into _r select lives_ok(
  $$update public.expenses
    set description = 'Edited by Ben', last_edited_by = '00000000-0000-0000-0000-000000000082',
        updated_at = '2026-06-03T10:00:00Z', write_id = '82aaaaaa-0000-0000-0000-000000000003'
    where id = '82000000-0000-0000-0000-000000000001'$$,
  'a member can record themselves as last editor');

insert into _r select is(
  (select last_edited_by from public.expenses where id = '82000000-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-000000000082'::uuid, 'last editor is the member who edited');

-- ── Ana re-sends the stored value with a soft-delete: unchanged, so allowed.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000081","role":"authenticated"}';

insert into _r select lives_ok(
  $$update public.expenses
    set last_edited_by = '00000000-0000-0000-0000-000000000082', deleted_at = '2026-06-04T10:00:00Z',
        updated_at = '2026-06-04T10:00:00Z', write_id = '82aaaaaa-0000-0000-0000-000000000004'
    where id = '82000000-0000-0000-0000-000000000001'$$,
  're-sending the stored last editor is allowed');

insert into _r select ok(
  (select deleted_at is not null from public.expenses where id = '82000000-0000-0000-0000-000000000001'),
  'the write that re-sent the stored last editor applied');

-- ── Inserts: the RPC records the caller; a direct insert cannot name someone else.
select public.create_expense_with_payments_and_splits(
  '{"id":"82000000-0000-0000-0000-000000000002","trip_id":"81111111-1111-1111-1111-111111111111","amount":"12","currency":"EUR","description":"Edited offline","expense_date":"2026-06-05","payment_method":"card","last_edited_by":"00000000-0000-0000-0000-000000000082"}'::jsonb,
  '[{"trip_person_id":"80000000-0000-0000-0000-000000000001","amount_paid":"12","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"80000000-0000-0000-0000-000000000001","amount_owed":"12","split_type":"equal"}]'::jsonb
);

insert into _r select is(
  (select last_edited_by from public.expenses where id = '82000000-0000-0000-0000-000000000002'),
  '00000000-0000-0000-0000-000000000081'::uuid, 'the RPC records the caller as last editor');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, amount, currency, description, expense_date, created_by, last_edited_by)
    values ('81111111-1111-1111-1111-111111111111', 5, 'EUR', 'Forged insert', '2026-06-06',
            '00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000082')$$,
  '42501', null, 'a direct insert cannot name another member as last editor');

-- ── Requests without a user (service role, maintenance) are not limited.
reset role;
set local request.jwt.claims to '';

insert into _r select lives_ok(
  $$update public.expenses set last_edited_by = '00000000-0000-0000-0000-000000000082'
    where id = '82000000-0000-0000-0000-000000000002'$$,
  'a request without a user can set any member as last editor');

insert into _r select is(
  (select last_edited_by from public.expenses where id = '82000000-0000-0000-0000-000000000002'),
  '00000000-0000-0000-0000-000000000082'::uuid, 'the server-side write applied');

insert into _r select * from finish();
select line from _r;
rollback;
