-- 14_membership_management.sql — update_trip_person_email + remove_trip_person:
-- placeholder-email repointing, claim after repoint, soft removal (removed_at),
-- access revocation, ledger integrity for removed members, restore via re-add,
-- and the deny paths for every mutation.

begin;
set search_path = extensions, public, pg_temp;

select plan(30);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000061', 'alpha14@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alpha"}'),
  ('00000000-0000-0000-0000-000000000062', 'bravo14@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bravo"}'),
  ('00000000-0000-0000-0000-000000000063', 'carla14@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Carla"}'),
  ('00000000-0000-0000-0000-000000000064', 'dora14@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Dora"}'),
  ('00000000-0000-0000-0000-000000000065', 'rita14@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Rita"}');

-- Alpha creates a trip, adds Bravo by email, a Splitwise-style placeholder
-- person Quinn, and a pending person Rita.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';
select public.create_trip_with_self(
  '61111111-1111-1111-1111-111111111111',
  '60000000-0000-0000-0000-000000000001',
  'Removal Trip'
);
select public.add_trip_person_by_email(
  '61111111-1111-1111-1111-111111111111', 'bravo14@test.tab', 'Bravo',
  '60000000-0000-0000-0000-000000000002');
select public.add_trip_person_by_email(
  '61111111-1111-1111-1111-111111111111', '60000000-0000-0000-0000-000000000003@users.tab', 'Quinn',
  '60000000-0000-0000-0000-000000000003');
select public.add_trip_person_by_email(
  '61111111-1111-1111-1111-111111111111', 'rita14@test.tab', 'Rita',
  '60000000-0000-0000-0000-000000000004');
reset role;

-- Bravo signs in and claims their row.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000062","role":"authenticated"}';
select count(*) from public.claim_trip_people_for_current_email();
reset role;

-- ── update_trip_person_email ────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';

insert into _r select lives_ok(
  $$select public.update_trip_person_email('60000000-0000-0000-0000-000000000003', 'Carla14@Test.tab ')$$,
  'member repoints a placeholder person to a real email');

insert into _r select is(
  (select email from public.trip_people where id = '60000000-0000-0000-0000-000000000003'),
  'carla14@test.tab',
  'repointed email is stored normalized');

insert into _r select throws_ok(
  $$select public.update_trip_person_email('60000000-0000-0000-0000-000000000002', 'elsewhere14@test.tab')$$,
  '42501', null, 'a joined member''s email cannot be changed');

insert into _r select throws_ok(
  $$select public.update_trip_person_email('60000000-0000-0000-0000-000000000004', 'bravo14@test.tab')$$,
  '23505', null, 'repointing to an email already in the trip is rejected');

insert into _r select throws_ok(
  $$select public.update_trip_person_email('60000000-0000-0000-0000-000000000004', 'not-an-email')$$,
  '22023', null, 'invalid emails are rejected');

reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000064","role":"authenticated"}';
insert into _r select throws_ok(
  $$select public.update_trip_person_email('60000000-0000-0000-0000-000000000004', 'dora14@test.tab')$$,
  '42501', null, 'non-members cannot edit person emails');
reset role;

-- Carla signs in: the repointed placeholder row is now claimable.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000063","role":"authenticated"}';
select count(*) from public.claim_trip_people_for_current_email();
reset role;

insert into _r select is(
  (select user_id from public.trip_people where id = '60000000-0000-0000-0000-000000000003'),
  '00000000-0000-0000-0000-000000000063'::uuid,
  'repointed person is claimed at the new email''s sign-in');

-- ── remove_trip_person ──────────────────────────────────────────────────────

-- Bravo authors an expense before being removed (paid 10, split 5/5).
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000062","role":"authenticated"}';
insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'eeeeeeee-0000-0000-0000-000000000061', 'trip_id', '61111111-1111-1111-1111-111111111111', 'amount', 10, 'currency', 'EUR', 'description', 'Dinner', 'expense_date', '2026-07-01'),
      jsonb_build_array(jsonb_build_object('trip_person_id', '60000000-0000-0000-0000-000000000002', 'amount_paid', 10, 'payment_mode', 'equal')),
      jsonb_build_array(
        jsonb_build_object('trip_person_id', '60000000-0000-0000-0000-000000000001', 'amount_owed', 5, 'split_type', 'equal'),
        jsonb_build_object('trip_person_id', '60000000-0000-0000-0000-000000000002', 'amount_owed', 5, 'split_type', 'equal')
      )
    )$$,
  'soon-to-be-removed member authors an expense');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';

insert into _r select throws_ok(
  $$select public.remove_trip_person('60000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'self-removal is blocked');

-- Direct client mutation of removed_at must be a no-op (no update policy).
update public.trip_people set removed_at = now()
where id = '60000000-0000-0000-0000-000000000002';
insert into _r select ok(
  (select removed_at is null from public.trip_people where id = '60000000-0000-0000-0000-000000000002'),
  'direct client removal has no effect');

reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000064","role":"authenticated"}';
insert into _r select throws_ok(
  $$select public.remove_trip_person('60000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'non-members cannot remove people');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';

insert into _r select lives_ok(
  $$select public.remove_trip_person('60000000-0000-0000-0000-000000000002')$$,
  'member removes another (claimed) member');

insert into _r select ok(
  (select removed_at is not null from public.trip_people where id = '60000000-0000-0000-0000-000000000002'),
  'removal stamps removed_at');

insert into _r select is(
  (select count(*)::int from public.activity_log
   where action = 'member_left' and entity_id = '60000000-0000-0000-0000-000000000002'),
  1,
  'removal emits one member_left activity event');

insert into _r select lives_ok(
  $$select public.remove_trip_person('60000000-0000-0000-0000-000000000002')$$,
  'removing an already-removed person is idempotent');

reset role;

-- Removed member loses trip access entirely.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000062","role":"authenticated"}';
insert into _r select is(
  (select count(*)::int from public.trips where id = '61111111-1111-1111-1111-111111111111'),
  0,
  'removed member can no longer see the trip');
reset role;

-- The removed member's ledger rows stay manageable by remaining members.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';

update public.expenses set deleted_at = now(), write_id = gen_random_uuid()
where id = 'eeeeeeee-0000-0000-0000-000000000061';
insert into _r select ok(
  (select deleted_at is not null from public.expenses where id = 'eeeeeeee-0000-0000-0000-000000000061'),
  'an expense authored by a removed member can still be soft-deleted');

insert into _r select lives_ok(
  $$insert into public.settlements (id, trip_id, from_person_id, to_person_id, amount, currency, settled_at, created_by)
    values ('feeeeeee-0000-0000-0000-000000000061', '61111111-1111-1111-1111-111111111111',
            '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002',
            5, 'EUR', now(), '00000000-0000-0000-0000-000000000061')$$,
  'members can still record settlements with a removed member');

insert into _r select throws_ok(
  $$select public.update_trip_person_email('60000000-0000-0000-0000-000000000002', 'later14@test.tab')$$,
  '42501', null, 'a removed person''s email cannot be edited');

-- Restore: re-adding the same email clears removed_at and keeps the claim.
insert into _r select lives_ok(
  $$select public.add_trip_person_by_email(
      '61111111-1111-1111-1111-111111111111', 'bravo14@test.tab', 'Bravo')$$,
  're-adding a removed member''s email restores them');

insert into _r select ok(
  (select removed_at is null and user_id = '00000000-0000-0000-0000-000000000062'
   from public.trip_people where id = '60000000-0000-0000-0000-000000000002'),
  'restore clears removed_at and keeps the claimed account');

-- One member_joined from the original pending insert, one from the restore.
insert into _r select is(
  (select count(*)::int from public.activity_log
   where action = 'member_joined' and entity_id = '60000000-0000-0000-0000-000000000002'),
  2,
  'restore emits a member_joined activity event');

reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000062","role":"authenticated"}';
insert into _r select is(
  (select count(*)::int from public.trips where id = '61111111-1111-1111-1111-111111111111'),
  1,
  'restored member sees the trip again');
reset role;

-- ── removed pending people: claim + suggestions ─────────────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';
insert into _r select lives_ok(
  $$select public.remove_trip_person('60000000-0000-0000-0000-000000000004')$$,
  'member removes a pending person');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000065","role":"authenticated"}';
select count(*) from public.claim_trip_people_for_current_email();
reset role;

insert into _r select ok(
  (select user_id is null and removed_at is not null
   from public.trip_people where id = '60000000-0000-0000-0000-000000000004'),
  'sign-in does not claim a removed pending row');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';
insert into _r select is(
  (select count(*)::int from public.suggest_trip_people('rita14')),
  0,
  'removed people are not suggested');

-- ── non-group containers are out of scope for removal ──────────────────────

select count(*) from public.resolve_or_create_non_group_container(
  '[{"email":"zed14@test.tab","display_name":"Zed"}]'::jsonb
);

insert into _r select throws_ok(
  format(
    $q$select public.remove_trip_person(%L)$q$,
    (select tp.id from public.trip_people tp
     join public.trips t on t.id = tp.trip_id
     where t.kind = 'non_group' and tp.email = 'zed14@test.tab')),
  'P0002', null, 'people in non-group containers cannot be removed');

insert into _r select throws_ok(
  format(
    $q$select public.update_trip_person_email(%L, 'zed-new14@test.tab')$q$,
    (select tp.id from public.trip_people tp
     join public.trips t on t.id = tp.trip_id
     where t.kind = 'non_group' and tp.email = 'zed14@test.tab')),
  'P0002', null, 'people in non-group containers cannot have emails edited');

reset role;

-- Removed members receive no push fan-out.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';
select public.remove_trip_person('60000000-0000-0000-0000-000000000002');
reset role;

insert into public.push_devices (id, user_id, apns_token)
values ('d0000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000062', 'token-bravo-14');

insert into _r select is(
  (select count(*)::int
   from public.push_targets_for_activity(
     (select id from public.activity_log
      where trip_id = '61111111-1111-1111-1111-111111111111'
      order by timestamp desc limit 1))
   where user_id = '00000000-0000-0000-0000-000000000062'),
  0,
  'removed members are excluded from push targets');

insert into _r select ok(
  (select count(*) > 0 from public.activity_log where trip_id = '61111111-1111-1111-1111-111111111111'),
  'activity exists for the push-target check');

insert into _r select * from finish();
select line from _r;
rollback;
