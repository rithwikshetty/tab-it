-- 11_sync_lww.sql — server-side last-write-wins semantics for synced rows.
-- Clients supply updated_at + write_id with every push; the server must
-- respect them, reject (silently skip) stale writes, never resurrect
-- tombstones, and keep stamping rows for metadata-less writes. Client stamps
-- are capped at five minutes past the server clock, and the trip activity
-- bump from expense writes does not restamp the trip.

begin;
set search_path = extensions, public, pg_temp;

select plan(29);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000051', 'lww@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Lww"}');

insert into public.trips (id, name, created_by)
values ('51111111-1111-1111-1111-111111111111', 'LWW Trip', '00000000-0000-0000-0000-000000000051');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values ('50000000-0000-0000-0000-000000000001', '51111111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000051', 'lww@test.tab', 'Lww',
        '00000000-0000-0000-0000-000000000051', now());

-- ── INSERT respects client-supplied sync metadata.
insert into public.expenses (id, trip_id, amount, currency, description, expense_date, payment_method, created_by, updated_at, write_id)
values ('52000000-0000-0000-0000-000000000001', '51111111-1111-1111-1111-111111111111',
        30, 'EUR', 'lww seed', '2026-06-01', 'card', '00000000-0000-0000-0000-000000000051',
        '2026-06-01T10:00:00Z', 'aaaaaaaa-0000-0000-0000-000000000001');
insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
values ('52000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 30, 'equal');
insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
values ('52000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 30, 'equal');

insert into _r select is(
  (select write_id from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
  'insert keeps the client write_id');

insert into _r select is(
  (select updated_at from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  '2026-06-01T10:00:00Z'::timestamptz,
  'insert keeps the client updated_at');

-- ── Metadata-less update still gets fresh server stamps (legacy/server path).
update public.expenses set description = 'server touched'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select isnt(
  (select write_id from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
  'metadata-less update stamps a fresh write_id');

insert into _r select ok(
  (select updated_at > '2026-06-01T10:00:00Z'::timestamptz
   from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'metadata-less update bumps updated_at');

-- Re-pin known metadata for the comparisons below. The metadata-less update
-- stamped the server clock, so the pin bypasses the sync trigger.
set local session_replication_role = replica;
update public.expenses
set description = 'pinned', updated_at = '2026-07-02T10:00:00Z', write_id = 'aaaaaaaa-0000-0000-0000-000000000002'
where id = '52000000-0000-0000-0000-000000000001';
set local session_replication_role = origin;

-- ── Newer client write applies and keeps the client write_id.
update public.expenses
set description = 'newer edit', updated_at = '2026-07-03T10:00:00Z', write_id = 'aaaaaaaa-0000-0000-0000-000000000003'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select description from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'newer edit', 'newer client write applies');

insert into _r select is(
  (select write_id from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'aaaaaaaa-0000-0000-0000-000000000003'::uuid,
  'newer client write keeps its write_id');

-- ── Older client write is silently skipped.
update public.expenses
set description = 'stale edit', updated_at = '2026-07-01T09:00:00Z', write_id = 'aaaaaaaa-0000-0000-0000-000000000004'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select description from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'newer edit', 'stale client write does not change content');

insert into _r select is(
  (select write_id from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'aaaaaaaa-0000-0000-0000-000000000003'::uuid,
  'stale client write does not change write_id');

-- ── Equal updated_at: higher write_id wins, lower loses.
update public.expenses
set description = 'tie higher', updated_at = '2026-07-03T10:00:00Z', write_id = 'ffffffff-0000-0000-0000-000000000001'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select description from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'tie higher', 'timestamp tie: higher write_id wins');

update public.expenses
set description = 'tie lower', updated_at = '2026-07-03T10:00:00Z', write_id = 'bbbbbbbb-0000-0000-0000-000000000001'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select description from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'tie higher', 'timestamp tie: lower write_id loses');

-- ── Delete-wins: an incoming tombstone beats a newer live edit.
update public.expenses
set deleted_at = '2026-08-01T10:00:00Z', updated_at = '2026-07-01T08:00:00Z', write_id = 'cccccccc-0000-0000-0000-000000000001'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select deleted_at from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  '2026-08-01T10:00:00Z'::timestamptz,
  'older incoming delete applies against a newer live row (delete-wins)');

-- A tombstone is never resurrected, even by a newer live update.
insert into _r select lives_ok(
  $$update public.expenses
    set deleted_at = null, description = 'resurrected', updated_at = '2026-08-02T10:00:00Z', write_id = 'cccccccc-0000-0000-0000-000000000002'
    where id = '52000000-0000-0000-0000-000000000001'$$,
  'live update against a tombstone does not error');

insert into _r select ok(
  (select deleted_at is not null from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'live update against a tombstone is ignored (delete-wins)');

-- ── RPC carries client metadata and respects LWW for the whole ledger.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000051","role":"authenticated"}';

select public.create_expense_with_payments_and_splits(
  '{"id":"52000000-0000-0000-0000-000000000002","trip_id":"51111111-1111-1111-1111-111111111111","amount":"40","currency":"EUR","description":"rpc seed","expense_date":"2026-06-02","payment_method":"card","updated_at":"2026-06-02T08:00:00Z","write_id":"dddddddd-0000-0000-0000-000000000001"}'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_paid":"40","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_owed":"40","split_type":"equal"}]'::jsonb
);

insert into _r select is(
  (select write_id from public.expenses where id = '52000000-0000-0000-0000-000000000002'),
  'dddddddd-0000-0000-0000-000000000001'::uuid,
  'RPC insert keeps the client write_id');

-- Stale RPC edit: older updated_at must change neither the row nor the ledgers.
select public.create_expense_with_payments_and_splits(
  '{"id":"52000000-0000-0000-0000-000000000002","trip_id":"51111111-1111-1111-1111-111111111111","amount":"99","currency":"EUR","description":"rpc stale","expense_date":"2026-06-02","payment_method":"card","updated_at":"2026-06-01T08:00:00Z","write_id":"dddddddd-0000-0000-0000-000000000002"}'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_paid":"99","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_owed":"99","split_type":"equal"}]'::jsonb
);

insert into _r select is(
  (select amount from public.expenses where id = '52000000-0000-0000-0000-000000000002'),
  40::numeric, 'stale RPC edit leaves the expense amount');

insert into _r select is(
  (select amount_owed from public.expense_splits where expense_id = '52000000-0000-0000-0000-000000000002'),
  40::numeric, 'stale RPC edit leaves the splits ledger');

-- Newer RPC edit applies row + ledgers.
select public.create_expense_with_payments_and_splits(
  '{"id":"52000000-0000-0000-0000-000000000002","trip_id":"51111111-1111-1111-1111-111111111111","amount":"60","currency":"EUR","description":"rpc newer","expense_date":"2026-06-02","payment_method":"card","updated_at":"2026-06-03T08:00:00Z","write_id":"dddddddd-0000-0000-0000-000000000003"}'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_paid":"60","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_owed":"60","split_type":"equal"}]'::jsonb
);

insert into _r select is(
  (select amount from public.expenses where id = '52000000-0000-0000-0000-000000000002'),
  60::numeric, 'newer RPC edit applies the expense amount');

insert into _r select is(
  (select amount_owed from public.expense_splits where expense_id = '52000000-0000-0000-0000-000000000002'),
  60::numeric, 'newer RPC edit replaces the splits ledger');

insert into _r select is(
  (select write_id from public.expenses where id = '52000000-0000-0000-0000-000000000002'),
  'dddddddd-0000-0000-0000-000000000003'::uuid,
  'newer RPC edit keeps its client write_id');

-- Legacy RPC payload (no metadata) still applies with fresh stamps.
select public.create_expense_with_payments_and_splits(
  '{"id":"52000000-0000-0000-0000-000000000002","trip_id":"51111111-1111-1111-1111-111111111111","amount":"70","currency":"EUR","description":"rpc legacy","expense_date":"2026-06-02","payment_method":"card"}'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_paid":"70","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000001","amount_owed":"70","split_type":"equal"}]'::jsonb
);

insert into _r select is(
  (select amount from public.expenses where id = '52000000-0000-0000-0000-000000000002'),
  70::numeric, 'metadata-less RPC edit still applies');

-- ── A trip rename stamped before a later expense still applies.
-- The trip's last edit is at 2026-07-01; a phone renames it offline at
-- 2026-07-02 (T1); an expense lands now (T2, server clock, after T1); then the
-- rename is pushed with its T1 stamp.
reset role;
insert into public.trips (id, name, created_by, updated_at, write_id)
values ('53333333-3333-3333-3333-333333333333', 'Before rename', '00000000-0000-0000-0000-000000000051',
        '2026-07-01T00:00:00Z', 'eeeeeeee-0000-0000-0000-000000000001');
insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values ('50000000-0000-0000-0000-000000000003', '53333333-3333-3333-3333-333333333333',
        '00000000-0000-0000-0000-000000000051', 'lww@test.tab', 'Lww',
        '00000000-0000-0000-0000-000000000051', now());
create temp table _trip_before as
  select last_activity_at from public.trips where id = '53333333-3333-3333-3333-333333333333';
grant select on _trip_before to authenticated;

set local role authenticated;
select public.create_expense_with_payments_and_splits(
  '{"id":"52000000-0000-0000-0000-000000000003","trip_id":"53333333-3333-3333-3333-333333333333","amount":"10","currency":"EUR","description":"after the rename","expense_date":"2026-07-03","payment_method":"card"}'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000003","amount_paid":"10","payment_mode":"equal"}]'::jsonb,
  '[{"trip_person_id":"50000000-0000-0000-0000-000000000003","amount_owed":"10","split_type":"equal"}]'::jsonb
);

insert into _r select ok(
  (select last_activity_at > (select last_activity_at from _trip_before)
   from public.trips where id = '53333333-3333-3333-3333-333333333333'),
  'an expense write bumps the trip''s last_activity_at');

insert into _r select ok(
  (select updated_at = '2026-07-01T00:00:00Z'::timestamptz
      and write_id = 'eeeeeeee-0000-0000-0000-000000000001'::uuid
   from public.trips where id = '53333333-3333-3333-3333-333333333333'),
  'the activity bump keeps the trip''s updated_at and write_id');

-- Stale rename (older than the trip's last edit) is still skipped.
with u as (
  update public.trips
  set name = 'Stale rename', updated_at = '2026-06-15T00:00:00Z', write_id = 'eeeeeeee-0000-0000-0000-000000000002'
  where id = '53333333-3333-3333-3333-333333333333'
  returning id
)
insert into _r select is((select count(*)::int from u), 0, 'a rename older than the trip''s last edit is skipped');

with u as (
  update public.trips
  set name = 'After rename', updated_at = '2026-07-02T00:00:00Z', write_id = 'eeeeeeee-0000-0000-0000-000000000003'
  where id = '53333333-3333-3333-3333-333333333333'
  returning id
)
insert into _r select is((select count(*)::int from u), 1, 'a rename stamped before a later expense updates one row');

insert into _r select is(
  (select name from public.trips where id = '53333333-3333-3333-3333-333333333333'),
  'After rename', 'the rename is applied');

-- ── Client stamps are capped at five minutes past the server clock.
reset role;
insert into public.expenses (id, trip_id, amount, currency, description, expense_date, payment_method, created_by, updated_at, write_id)
values ('52000000-0000-0000-0000-000000000004', '53333333-3333-3333-3333-333333333333',
        5, 'EUR', 'future clock', '2026-07-03', 'card', '00000000-0000-0000-0000-000000000051',
        '2099-01-01T00:00:00Z', 'abababab-0000-0000-0000-000000000001');

insert into _r select ok(
  (select updated_at <= clock_timestamp() + interval '5 minutes'
   from public.expenses where id = '52000000-0000-0000-0000-000000000004'),
  'insert caps a future client updated_at');

update public.expenses
set description = 'future edit', updated_at = '2099-01-02T00:00:00Z', write_id = 'abababab-0000-0000-0000-000000000002'
where id = '52000000-0000-0000-0000-000000000004';

insert into _r select ok(
  (select description = 'future edit'
      and updated_at > now()
      and updated_at <= clock_timestamp() + interval '5 minutes'
   from public.expenses where id = '52000000-0000-0000-0000-000000000004'),
  'update applies a future-clock edit with updated_at capped');

update public.expenses
set deleted_at = '2099-01-03T00:00:00Z', updated_at = '2099-01-03T00:00:00Z', write_id = 'abababab-0000-0000-0000-000000000003'
where id = '52000000-0000-0000-0000-000000000004';

insert into _r select ok(
  (select deleted_at > now() and deleted_at <= clock_timestamp() + interval '5 minutes'
   from public.expenses where id = '52000000-0000-0000-0000-000000000004'),
  'update caps a future client deleted_at');

-- A stamp inside the five-minute window is kept exactly.
create temp table _soon as select clock_timestamp() + interval '1 minute' as ts;
update public.trips
set name = 'Near future', updated_at = (select ts from _soon), write_id = 'eeeeeeee-0000-0000-0000-000000000004'
where id = '53333333-3333-3333-3333-333333333333';

insert into _r select is(
  (select updated_at from public.trips where id = '53333333-3333-3333-3333-333333333333'),
  (select ts from _soon),
  'a client updated_at within five minutes of the server clock is kept as sent');

insert into _r select * from finish();
select line from _r;
rollback;
