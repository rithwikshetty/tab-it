-- 01_schema.sql — schema shape for email-first trip people.

begin;
set search_path = extensions, public, pg_temp;

select plan(49);
create temp table _r (line text);

-- Tables
insert into _r select has_table('public', 'profiles',         'profiles exists');
insert into _r select has_table('public', 'trips',            'trips exists');
insert into _r select has_table('public', 'trip_people',      'trip_people exists');
insert into _r select has_table('public', 'categories',       'categories exists');
insert into _r select has_table('public', 'expenses',         'expenses exists');
insert into _r select has_table('public', 'expense_payments', 'expense_payments exists');
insert into _r select has_table('public', 'expense_splits',   'expense_splits exists');
insert into _r select has_table('public', 'settlements',      'settlements exists');
insert into _r select has_table('public', 'activity_log',     'activity_log exists');
insert into _r select has_table('public', 'push_devices',     'push_devices exists');
insert into _r select has_table('public', 'trip_mute_prefs',  'trip_mute_prefs exists');

-- Client RPCs
insert into _r select has_function('public', 'ensure_current_profile', array['text', 'text'], 'ensure_current_profile(text, text) exists');
insert into _r select has_function('public', 'create_trip_with_self', array['uuid', 'uuid', 'text'], 'create_trip_with_self(uuid, uuid, text) exists');
insert into _r select has_function('public', 'add_trip_person_by_email', array['uuid', 'text', 'text', 'uuid'], 'add_trip_person_by_email(uuid, text, text, uuid) exists');
insert into _r select has_function('public', 'claim_trip_people_for_current_email', array[]::text[], 'claim_trip_people_for_current_email() exists');
insert into _r select has_function('public', 'suggest_trip_people', array['text', 'integer'], 'suggest_trip_people(text, int) exists');
insert into _r select has_function('public', 'create_expense_with_payments_and_splits', array['jsonb', 'jsonb', 'jsonb'], 'create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) exists');

-- Primary keys and FKs
insert into _r select col_is_pk('public', 'profiles',         'id',                             'profiles.id PK');
insert into _r select col_is_pk('public', 'trips',            'id',                             'trips.id PK');
insert into _r select col_is_pk('public', 'trip_people',      'id',                             'trip_people.id PK');
insert into _r select col_is_pk('public', 'expense_payments', array['expense_id', 'trip_person_id'], 'expense_payments composite PK');
insert into _r select col_is_pk('public', 'expense_splits',   array['expense_id', 'trip_person_id'], 'expense_splits composite PK');
insert into _r select col_is_pk('public', 'settlements',      'id',                             'settlements.id PK');
insert into _r select col_is_fk('public', 'trips',            'created_by',       'trips.created_by FK');
insert into _r select col_is_fk('public', 'trip_people',      'trip_id',          'trip_people.trip_id FK');
insert into _r select col_is_fk('public', 'trip_people',      'user_id',          'trip_people.user_id FK');
insert into _r select col_is_fk('public', 'expenses',         'created_by',       'expenses.created_by FK');
insert into _r select col_is_fk('public', 'expense_payments', 'trip_person_id',   'expense_payments.trip_person_id FK');
insert into _r select col_is_fk('public', 'expense_splits',   'trip_person_id',   'expense_splits.trip_person_id FK');
insert into _r select col_is_fk('public', 'settlements',      'from_person_id',   'settlements.from_person_id FK');
insert into _r select col_is_fk('public', 'settlements',      'to_person_id',     'settlements.to_person_id FK');
insert into _r select has_column('public', 'expenses', 'payment_method', 'expenses.payment_method exists');
insert into _r select has_column('public', 'expense_splits', 'share_units', 'expense_splits.share_units exists');
insert into _r select has_column('public', 'expense_splits', 'percentage', 'expense_splits.percentage exists');

-- RLS
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),         'RLS enabled: profiles');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.trips'::regclass),            'RLS enabled: trips');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.trip_people'::regclass),      'RLS enabled: trip_people');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.categories'::regclass),       'RLS enabled: categories');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.expenses'::regclass),         'RLS enabled: expenses');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.expense_payments'::regclass), 'RLS enabled: expense_payments');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.expense_splits'::regclass),   'RLS enabled: expense_splits');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.settlements'::regclass),      'RLS enabled: settlements');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.activity_log'::regclass),     'RLS enabled: activity_log');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.push_devices'::regclass),     'RLS enabled: push_devices');
insert into _r select ok((select relrowsecurity from pg_class where oid = 'public.trip_mute_prefs'::regclass),  'RLS enabled: trip_mute_prefs');

-- Realtime publication membership (required for cross-device live updates).
insert into _r select ok(
  exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'trips'
  ),
  'supabase_realtime includes public.trips'
);
insert into _r select ok(
  exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'trip_people'
  ),
  'supabase_realtime includes public.trip_people'
);
insert into _r select ok(
  exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'expenses'
  ),
  'supabase_realtime includes public.expenses'
);
insert into _r select ok(
  exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'settlements'
  ),
  'supabase_realtime includes public.settlements'
);

insert into _r select * from finish();
select line from _r;
rollback;
