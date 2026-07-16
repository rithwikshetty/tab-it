-- 15_trip_invites.sql — trip invite links: get_or_create/revoke/join RPCs,
-- token stability + rotation after revoke, joining as new member / claiming a
-- pending email row / restoring a removed member, RLS allow+deny on the
-- invites table, and deny paths for non-members, revoked tokens, non-group
-- containers, and deleted trips.

begin;
set search_path = extensions, public, pg_temp;

select plan(30);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000071', 'alpha15@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alpha"}'),
  ('00000000-0000-0000-0000-000000000072', 'bravo15@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bravo"}'),
  ('00000000-0000-0000-0000-000000000073', 'rita15@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Rita"}'),
  ('00000000-0000-0000-0000-000000000074', 'dora15@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Dora"}'),
  ('00000000-0000-0000-0000-000000000075', 'quinn15@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Quinn"}');

-- Alpha creates a trip and pre-adds Rita and Quinn by email.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';
select public.create_trip_with_self(
  '71111111-1111-1111-1111-111111111111',
  '70000000-0000-0000-0000-000000000001',
  'Invite Trip'
);
select public.add_trip_person_by_email(
  '71111111-1111-1111-1111-111111111111', 'rita15@test.tab', 'Rita',
  '70000000-0000-0000-0000-000000000002');
select public.add_trip_person_by_email(
  '71111111-1111-1111-1111-111111111111', 'quinn15@test.tab', 'Quinn',
  '70000000-0000-0000-0000-000000000003');
reset role;

-- ── creating the link ───────────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000074","role":"authenticated"}';
insert into _r select throws_ok(
  $$select public.get_or_create_trip_invite('71111111-1111-1111-1111-111111111111')$$,
  '42501', null, 'non-members cannot create invite links');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';

insert into _r select lives_ok(
  $$select public.get_or_create_trip_invite('71111111-1111-1111-1111-111111111111')$$,
  'member creates the trip invite link');

insert into _r select ok(
  (select token ~ '^[0-9a-f]{32}$' from public.trip_invites
   where trip_id = '71111111-1111-1111-1111-111111111111' and revoked_at is null),
  'token is 32 hex chars');

insert into _r select is(
  (select (public.get_or_create_trip_invite('71111111-1111-1111-1111-111111111111')).token),
  (select token from public.trip_invites
   where trip_id = '71111111-1111-1111-1111-111111111111' and revoked_at is null),
  'get_or_create returns the same active token on repeat calls');

-- Direct client mutation of revoked_at must be a no-op (no update policy).
update public.trip_invites set revoked_at = now()
where trip_id = '71111111-1111-1111-1111-111111111111';
insert into _r select ok(
  (select count(*) = 1 from public.trip_invites
   where trip_id = '71111111-1111-1111-1111-111111111111' and revoked_at is null),
  'direct client revocation has no effect');

insert into _r select is(
  (select count(*)::int from public.trip_invites
   where trip_id = '71111111-1111-1111-1111-111111111111'),
  1,
  'members can read their trip''s invites');

reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000074","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.trip_invites
   where trip_id = '71111111-1111-1111-1111-111111111111'),
  0,
  'non-members cannot read invites (token stays secret)');

insert into _r select throws_ok(
  $$insert into public.trip_invites (trip_id, token, created_by)
    values ('71111111-1111-1111-1111-111111111111',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            '00000000-0000-0000-0000-000000000074')$$,
  '42501', null, 'direct client inserts into trip_invites are rejected');

reset role;

-- Capture the active token for join calls (test session is table owner).
create temp table _tok as
  select token from public.trip_invites
  where trip_id = '71111111-1111-1111-1111-111111111111' and revoked_at is null;
grant select on _tok to authenticated;

-- ── joining: new member ─────────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000072","role":"authenticated"}';

insert into _r select lives_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok)),
  'a signed-in non-member joins with the link');

insert into _r select is(
  (select count(*)::int from public.trips where id = '71111111-1111-1111-1111-111111111111'),
  1,
  'joiner can see the trip');

insert into _r select ok(
  (select user_id = '00000000-0000-0000-0000-000000000072'
      and joined_at is not null and removed_at is null
   from public.trip_people
   where trip_id = '71111111-1111-1111-1111-111111111111' and email = 'bravo15@test.tab'),
  'join creates a claimed member row with the auth email');

insert into _r select lives_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok)),
  'joining again is idempotent');

insert into _r select is(
  (select count(*)::int from public.trip_people
   where trip_id = '71111111-1111-1111-1111-111111111111'
     and user_id = '00000000-0000-0000-0000-000000000072'),
  1,
  'repeat joins do not duplicate the member');

insert into _r select is(
  (select count(*)::int from public.activity_log a
   join public.trip_people tp on tp.id = a.entity_id
   where a.action = 'member_joined' and tp.email = 'bravo15@test.tab'),
  1,
  'link join emits one member_joined activity event');

reset role;

-- ── joining: pre-added email is claimed, not duplicated ────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000073","role":"authenticated"}';

insert into _r select lives_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok)),
  'a pre-added person joins with the link');

insert into _r select ok(
  (select user_id = '00000000-0000-0000-0000-000000000073' and joined_at is not null
   from public.trip_people where id = '70000000-0000-0000-0000-000000000002'),
  'their pending row is claimed in place');

insert into _r select is(
  (select count(*)::int from public.trip_people
   where trip_id = '71111111-1111-1111-1111-111111111111' and email = 'rita15@test.tab'),
  1,
  'claiming via link does not duplicate the person');

reset role;

-- ── joining: removed people are restored ────────────────────────────────────

-- A removed pending person: the link claims and restores their row.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';
select public.remove_trip_person('70000000-0000-0000-0000-000000000003');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000075","role":"authenticated"}';
insert into _r select lives_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok)),
  'a removed pending person rejoins with the link');
reset role;

insert into _r select ok(
  (select user_id = '00000000-0000-0000-0000-000000000075' and removed_at is null
   from public.trip_people where id = '70000000-0000-0000-0000-000000000003'),
  'their original row is restored and claimed, keeping the ledger identity');

-- A removed claimed member: holding the link is equivalent to being re-added.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';
insert into _r select lives_ok(
  format(
    $q$select public.remove_trip_person(%L)$q$,
    (select id from public.trip_people
     where trip_id = '71111111-1111-1111-1111-111111111111' and email = 'bravo15@test.tab')),
  'member removes the link joiner');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000072","role":"authenticated"}';
insert into _r select lives_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok)),
  'a removed claimed member rejoins with the link');
reset role;

insert into _r select ok(
  (select removed_at is null from public.trip_people
   where trip_id = '71111111-1111-1111-1111-111111111111' and email = 'bravo15@test.tab'),
  'rejoin clears removed_at on their existing row');

-- ── bad tokens and revocation ───────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000074","role":"authenticated"}';

insert into _r select throws_ok(
  $$select public.join_trip_with_invite('00000000000000000000000000000000')$$,
  'P0002', null, 'an unknown token is rejected');

insert into _r select throws_ok(
  $$select public.revoke_trip_invite('71111111-1111-1111-1111-111111111111')$$,
  '42501', null, 'non-members cannot revoke invite links');

reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';
insert into _r select lives_ok(
  $$select public.revoke_trip_invite('71111111-1111-1111-1111-111111111111')$$,
  'member revokes the invite link');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000074","role":"authenticated"}';
insert into _r select throws_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok)),
  'P0002', null, 'a revoked token no longer admits anyone');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';
select public.get_or_create_trip_invite('71111111-1111-1111-1111-111111111111');
reset role;

create temp table _tok2 as
  select token from public.trip_invites
  where trip_id = '71111111-1111-1111-1111-111111111111' and revoked_at is null;
grant select on _tok2 to authenticated;

insert into _r select isnt(
  (select token from _tok2),
  (select token from _tok),
  'sharing again after revoke mints a fresh token');

-- ── non-group containers and deleted trips ──────────────────────────────────

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';

select count(*) from public.resolve_or_create_non_group_container(
  '[{"email":"zed15@test.tab","display_name":"Zed"}]'::jsonb
);

insert into _r select throws_ok(
  format(
    $q$select public.get_or_create_trip_invite(%L)$q$,
    (select t.id from public.trips t
     join public.trip_people tp on tp.trip_id = t.id
     where t.kind = 'non_group' and tp.email = 'zed15@test.tab')),
  '42501', null, 'non-group containers cannot have invite links');

-- Soft-delete the trip: its invite stops working entirely.
update public.trips
set deleted_at = now(), updated_at = clock_timestamp(), write_id = gen_random_uuid()
where id = '71111111-1111-1111-1111-111111111111';

insert into _r select throws_ok(
  format($q$select public.join_trip_with_invite(%L)$q$, (select token from _tok2)),
  'P0002', null, 'a deleted trip''s token no longer admits anyone');

insert into _r select throws_ok(
  $$select public.get_or_create_trip_invite('71111111-1111-1111-1111-111111111111')$$,
  'P0002', null, 'no invite links for deleted trips');

reset role;

insert into _r select * from finish();
select line from _r;
rollback;
