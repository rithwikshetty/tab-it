-- 08_activity_notifications.sql — activity_log event-sourcing triggers,
-- read cursor, mute, and unread badge count.

begin;
set search_path = extensions, public, pg_temp;

select plan(17);
create temp table _r (line text);
grant insert, select on _r to authenticated;

-- Schema surface
insert into _r select has_column('public', 'profiles', 'activity_last_seen_at', 'profiles.activity_last_seen_at exists');
insert into _r select has_function('public', 'mark_activity_seen', array['timestamptz'], 'mark_activity_seen(timestamptz) exists');
insert into _r select has_function('public', 'unread_activity_count', array['uuid'], 'unread_activity_count(uuid) exists');
insert into _r select ok(
  has_function_privilege('service_role', 'public.push_targets_for_activity(uuid)', 'execute'),
  'service_role can execute push_targets_for_activity for edge fan-out');

-- Fixtures: alice + bob (profiles auto-created by handle_new_user)
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- alice creates a trip (self-add must NOT emit member_joined) and adds bob (must emit member_joined)
select public.create_trip_with_self('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000001', 'Lisbon');
select public.add_trip_person_by_email('11111111-1111-1111-1111-111111111111', 'bob@test.tab', 'Bob', '10000000-0000-0000-0000-000000000002');

-- After setup: exactly trip_created + member_joined(bob) = 2 (creator self-add is skipped)
insert into _r select is(
  (select count(*)::int from public.activity_log where trip_id = '11111111-1111-1111-1111-111111111111'),
  2, 'trip_created + member_joined only (self-add skipped)');
insert into _r select is(
  (select count(*)::int from public.activity_log where action = 'member_joined' and snapshot_json->>'member_name' = 'Bob'),
  1, 'member_joined emitted for added member');

-- Bob claims the pending invite so unread counts and mute prefs treat him as a member.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select public.claim_trip_people_for_current_email();

-- Make event chronology deterministic inside this single transaction. Initial
-- trip/member events predate Bob's membership; later lifecycle events occur at
-- the join boundary and are included by timestamp >= joined_at.
reset role;
update public.activity_log
set timestamp = transaction_timestamp() - interval '1 microsecond'
where trip_id = '11111111-1111-1111-1111-111111111111';
update public.trip_people
set joined_at = transaction_timestamp()
where id = '10000000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- Expense lifecycle
select public.create_expense_with_payments_and_splits(
  jsonb_build_object('id','aaaaaaaa-0000-0000-0000-000000000001','trip_id','11111111-1111-1111-1111-111111111111','amount',50,'currency','EUR','description','Dinner','expense_date','2026-05-01'),
  jsonb_build_array(jsonb_build_object('trip_person_id','10000000-0000-0000-0000-000000000001','amount_paid',50,'payment_mode','equal')),
  jsonb_build_array(jsonb_build_object('trip_person_id','10000000-0000-0000-0000-000000000001','amount_owed',50,'split_type','equal')));
insert into _r select is(
  (select count(*)::int from public.activity_log where action='expense_created' and entity_id='aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'expense_created emitted on insert');

-- Meaningful edit -> expense_updated
select public.create_expense_with_payments_and_splits(
  jsonb_build_object('id','aaaaaaaa-0000-0000-0000-000000000001','trip_id','11111111-1111-1111-1111-111111111111','amount',80,'currency','EUR','description','Dinner','expense_date','2026-05-01','last_edited_by','x'),
  jsonb_build_array(jsonb_build_object('trip_person_id','10000000-0000-0000-0000-000000000001','amount_paid',80,'payment_mode','equal')),
  jsonb_build_array(jsonb_build_object('trip_person_id','10000000-0000-0000-0000-000000000001','amount_owed',80,'split_type','equal')));
insert into _r select is(
  (select count(*)::int from public.activity_log where action='expense_updated' and entity_id='aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'expense_updated emitted on meaningful edit');

-- No-op edit (identical fields) -> NO new event (idempotency vs re-sync)
select public.create_expense_with_payments_and_splits(
  jsonb_build_object('id','aaaaaaaa-0000-0000-0000-000000000001','trip_id','11111111-1111-1111-1111-111111111111','amount',80,'currency','EUR','description','Dinner','expense_date','2026-05-01','last_edited_by','x'),
  jsonb_build_array(jsonb_build_object('trip_person_id','10000000-0000-0000-0000-000000000001','amount_paid',80,'payment_mode','equal')),
  jsonb_build_array(jsonb_build_object('trip_person_id','10000000-0000-0000-0000-000000000001','amount_owed',80,'split_type','equal')));
insert into _r select is(
  (select count(*)::int from public.activity_log where entity_id='aaaaaaaa-0000-0000-0000-000000000001'),
  2, 'no-op edit emits nothing (still create+update)');

-- Soft delete -> expense_deleted
update public.expenses set deleted_at = clock_timestamp() where id = 'aaaaaaaa-0000-0000-0000-000000000001';
insert into _r select is(
  (select count(*)::int from public.activity_log where action='expense_deleted' and entity_id='aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'expense_deleted emitted on soft delete');

-- Settlement create
insert into public.settlements (id, trip_id, from_person_id, to_person_id, amount, currency, created_by)
values ('bbbbbbbb-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',20,'EUR','00000000-0000-0000-0000-000000000001');
insert into _r select is(
  (select count(*)::int from public.activity_log where action='settlement_created' and entity_id='bbbbbbbb-0000-0000-0000-000000000001'),
  1, 'settlement_created emitted');

-- Clients must not be able to forge activity rows directly: activity_log is
-- written by domain triggers, and every insert fans out to Activity/push.
insert into _r select throws_ok(
  $$insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id, snapshot_json)
      values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'trip_updated', 'trip', '11111111-1111-1111-1111-111111111111', '{"trip_name":"Forged"}')$$,
  '42501', null, 'direct client activity_log insert denied');

-- Badge counts (run as owner: execute revoked from authenticated)
reset role;
-- Alice authored everything -> 0 unread. Bob joined after trip_created and
-- member_joined, so only the four later lifecycle events are unread.
insert into _r select is(public.unread_activity_count('00000000-0000-0000-0000-000000000001'), 0, 'actor sees 0 unread (own actions excluded)');
insert into _r select is(public.unread_activity_count('00000000-0000-0000-0000-000000000002'), 4, 'member sees only events at or after joining as unread');

-- bob marks seen -> 0 unread
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select public.mark_activity_seen(null);
reset role;
insert into _r select is(public.unread_activity_count('00000000-0000-0000-0000-000000000002'), 0, 'unread clears after mark_activity_seen');

-- bob mutes the trip; a new alice event must NOT count for bob
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into public.trip_mute_prefs (trip_id, user_id) values ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000002');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into public.settlements (id, trip_id, from_person_id, to_person_id, amount, currency, created_by)
values ('bbbbbbbb-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',5,'EUR','00000000-0000-0000-0000-000000000001');
reset role;
insert into _r select is(public.unread_activity_count('00000000-0000-0000-0000-000000000002'), 0, 'muted trip events excluded from unread badge');

-- Client hard deletion of trip people is denied; member removals must be
-- server-owned so one member cannot remove another member or pending invite.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select public.add_trip_person_by_email('11111111-1111-1111-1111-111111111111', 'temp@test.tab', 'Temp', '10000000-0000-0000-0000-000000000003');
delete from public.trip_people where id = '10000000-0000-0000-0000-000000000003';
reset role;
insert into _r select ok(
  (select count(*)::int from public.trip_people where id = '10000000-0000-0000-0000-000000000003') = 1
  and (select count(*)::int from public.activity_log where action='member_left') = 0,
  'direct client trip_people hard delete has no effect and emits no member_left event');

insert into _r select * from finish();
select line from _r;
rollback;
