-- 18_receipt_sweep.sql — orphaned_receipt_objects lists only receipt objects
-- that no live expense points at and that have been left alone for 30 days,
-- only the service role can call it, and the daily job asks the edge function
-- only when its URL is configured.

begin;
set search_path = extensions, public, pg_temp;

select plan(13);
create temp table _r (line text);
grant insert, select on _r to authenticated, anon, service_role;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000091', 'ana91@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Ana"}');

insert into public.trips (id, name, created_by)
values ('91111111-1111-1111-1111-111111111111', 'Sweep Trip', '00000000-0000-0000-0000-000000000091');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values ('90000000-0000-0000-0000-000000000001', '91111111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000091', 'ana91@test.tab', 'Ana',
        '00000000-0000-0000-0000-000000000091', now());

-- 01 keeps its photo. 02 had its photo removed long ago. 03 was deleted long
-- ago. 04 had its photo removed this week. 05 keeps a photo stored under the
-- older receipts/ prefix. 06 had a photo under that prefix removed long ago.
insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by, receipt_storage_path, deleted_at, updated_at)
values
  ('92000000-0000-0000-0000-000000000001', '91111111-1111-1111-1111-111111111111', 10, 'EUR', 'Kept', '2026-06-01',
   '00000000-0000-0000-0000-000000000091', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000001.jpg', null, now() - interval '40 days'),
  ('92000000-0000-0000-0000-000000000002', '91111111-1111-1111-1111-111111111111', 10, 'EUR', 'Photo removed', '2026-06-01',
   '00000000-0000-0000-0000-000000000091', null, null, now() - interval '40 days'),
  ('92000000-0000-0000-0000-000000000003', '91111111-1111-1111-1111-111111111111', 10, 'EUR', 'Deleted', '2026-06-01',
   '00000000-0000-0000-0000-000000000091', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000003.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('92000000-0000-0000-0000-000000000004', '91111111-1111-1111-1111-111111111111', 10, 'EUR', 'Photo removed this week', '2026-06-01',
   '00000000-0000-0000-0000-000000000091', null, null, now() - interval '5 days'),
  ('92000000-0000-0000-0000-000000000005', '91111111-1111-1111-1111-111111111111', 10, 'EUR', 'Kept, older prefix', '2026-06-01',
   '00000000-0000-0000-0000-000000000091', 'receipts/91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000005.jpg', null, now() - interval '40 days'),
  ('92000000-0000-0000-0000-000000000006', '91111111-1111-1111-1111-111111111111', 10, 'EUR', 'Photo removed, older prefix', '2026-06-01',
   '00000000-0000-0000-0000-000000000091', null, null, now() - interval '40 days');

insert into storage.buckets (id, name) values ('sweep-test-other', 'sweep-test-other');

insert into storage.objects (bucket_id, name, created_at, updated_at)
values
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000001.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000002.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000003.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000004.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('receipts', 'receipts/91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000005.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('receipts', 'receipts/91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000006.jpg', now() - interval '40 days', now() - interval '40 days'),
  -- No expense row at all: one old, one uploaded this week, one replaced this week.
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-00000000000a.jpg', now() - interval '40 days', now() - interval '40 days'),
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-00000000000b.jpg', now() - interval '5 days', now() - interval '5 days'),
  ('receipts', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-00000000000c.jpg', now() - interval '40 days', now() - interval '5 days'),
  -- Not a receipt path, and the same name as an orphan in another bucket.
  ('receipts', 'notes.txt', now() - interval '40 days', now() - interval '40 days'),
  ('sweep-test-other', '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000002.jpg', now() - interval '40 days', now() - interval '40 days');

insert into _r select has_function('public', 'orphaned_receipt_objects', array['integer', 'timestamp with time zone'], 'orphaned_receipt_objects(integer, timestamptz) exists');
insert into _r select has_function('private', 'request_receipt_sweep', array[]::text[], 'request_receipt_sweep() exists');

-- ── What the sweep would remove.
insert into _r select results_eq(
  $$select name from public.orphaned_receipt_objects() where name like '%91111111-1111-1111-1111-111111111111/%'$$,
  $$values
    ('91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000002.jpg'),
    ('91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000003.jpg'),
    ('91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-00000000000a.jpg'),
    ('receipts/91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000006.jpg')$$,
  'lists the photo that was removed, the deleted expense''s photo and the photos with no expense, once they are 30 days old');

insert into _r select is(
  (select count(*)::int from public.orphaned_receipt_objects() where name = 'notes.txt'),
  0, 'an object that is not named like a receipt is left alone');

insert into _r select is(
  (select count(*)::int from public.orphaned_receipt_objects(1)),
  1, 'the limit caps one run');

insert into _r select is(
  (select count(*)::int from public.orphaned_receipt_objects(500, now() - interval '50 days')
   where name like '%91111111-1111-1111-1111-111111111111/%'),
  0, 'an earlier cutoff lists nothing newer than it');

-- A phone that was offline pushes a copy of expense 02 that still names the
-- photo, stamped before the cutoff, so only the path keeps the photo.
update public.expenses
set receipt_storage_path = '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000002.jpg',
    updated_at = now() - interval '35 days', write_id = '92aaaaaa-0000-0000-0000-000000000002'
where id = '92000000-0000-0000-0000-000000000002';

insert into _r select is(
  (select count(*)::int from public.orphaned_receipt_objects()
   where name = '91111111-1111-1111-1111-111111111111/92000000-0000-0000-0000-000000000002.jpg'),
  0, 'a photo an expense points at again is no longer listed');

-- ── Only the service role can list them.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000091","role":"authenticated"}';
insert into _r select throws_ok(
  $$select * from public.orphaned_receipt_objects()$$,
  '42501', null, 'a signed-in user cannot list orphaned receipts');

set local role anon;
set local request.jwt.claims to '';
insert into _r select throws_ok(
  $$select * from public.orphaned_receipt_objects()$$,
  '42501', null, 'a signed-out caller cannot list orphaned receipts');

set local role service_role;
insert into _r select lives_ok(
  $$select * from public.orphaned_receipt_objects()$$,
  'the service role can list orphaned receipts');
reset role;

-- ── The daily job.
insert into _r select is(
  (select schedule || ' | ' || command from cron.job where jobname = 'sweep-receipts'),
  '17 3 * * * | select private.request_receipt_sweep()', 'the sweep-receipts job runs once a day');

delete from private.app_config where key = 'receipt_sweep_url';
create temp table _queued as select count(*)::int as n from net.http_request_queue;

select private.request_receipt_sweep();
insert into _r select is(
  (select count(*)::int from net.http_request_queue), (select n from _queued),
  'with no URL configured the job sends nothing');

insert into private.app_config (key, value) values ('receipt_sweep_url', 'http://127.0.0.1:9/sweep-receipts');
select private.request_receipt_sweep();
insert into _r select is(
  (select count(*)::int from net.http_request_queue), (select n + 1 from _queued),
  'with a URL configured the job queues one request');

insert into _r select * from finish();
select line from _r;
rollback;
