-- 11_sync_lww.sql — server-side last-write-wins semantics for synced rows.
-- Clients supply updated_at + write_id with every push; the server must
-- respect them, reject (silently skip) stale writes, never resurrect
-- tombstones, and keep stamping rows for metadata-less writes.

begin;
set search_path = extensions, public, pg_temp;

select plan(20);
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

-- Re-pin known metadata for the comparisons below.
update public.expenses
set description = 'pinned', updated_at = '2027-01-02T10:00:00Z', write_id = 'aaaaaaaa-0000-0000-0000-000000000002'
where id = '52000000-0000-0000-0000-000000000001';

-- ── Newer client write applies and keeps the client write_id.
update public.expenses
set description = 'newer edit', updated_at = '2027-01-03T10:00:00Z', write_id = 'aaaaaaaa-0000-0000-0000-000000000003'
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
set description = 'stale edit', updated_at = '2027-01-01T09:00:00Z', write_id = 'aaaaaaaa-0000-0000-0000-000000000004'
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
set description = 'tie higher', updated_at = '2027-01-03T10:00:00Z', write_id = 'ffffffff-0000-0000-0000-000000000001'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select description from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'tie higher', 'timestamp tie: higher write_id wins');

update public.expenses
set description = 'tie lower', updated_at = '2027-01-03T10:00:00Z', write_id = 'bbbbbbbb-0000-0000-0000-000000000001'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select description from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  'tie higher', 'timestamp tie: lower write_id loses');

-- ── Delete-wins: an incoming tombstone beats a newer live edit.
update public.expenses
set deleted_at = '2027-02-01T10:00:00Z', updated_at = '2027-01-01T08:00:00Z', write_id = 'cccccccc-0000-0000-0000-000000000001'
where id = '52000000-0000-0000-0000-000000000001';

insert into _r select is(
  (select deleted_at from public.expenses where id = '52000000-0000-0000-0000-000000000001'),
  '2027-02-01T10:00:00Z'::timestamptz,
  'older incoming delete applies against a newer live row (delete-wins)');

-- A tombstone is never resurrected, even by a newer live update.
insert into _r select lives_ok(
  $$update public.expenses
    set deleted_at = null, description = 'resurrected', updated_at = '2027-02-02T10:00:00Z', write_id = 'cccccccc-0000-0000-0000-000000000002'
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

reset role;

insert into _r select * from finish();
select line from _r;
rollback;
