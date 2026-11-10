-- Fictional trips for App Store screenshots. Run on the local stack only,
-- after `bash supabase/scripts/reset_local.sh`:
--   docker exec -i supabase_db_tab-local psql -U postgres -d postgres \
--     --set ON_ERROR_STOP=1 < docs/app-store/screenshots/demo-data.sql
-- Sign in as mock@tab.local. Every name and amount here is made up.

begin;
set search_path = extensions, public, pg_temp;

insert into auth.users (id, email, instance_id, aud, role, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select u.id, u.email, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  crypt('local-only-password', gen_salt('bf')), now(), '', '', '', '',
  '{"provider":"email","providers":["email"]}', jsonb_build_object('display_name', u.name), now(), now()
from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'dan@tab.local', 'Dan'),
  ('a0000000-0000-4000-8000-000000000002', 'maya@tab.local', 'Maya'),
  ('a0000000-0000-4000-8000-000000000003', 'priya@tab.local', 'Priya'),
  ('a0000000-0000-4000-8000-000000000004', 'jess@tab.local', 'Jess'),
  ('a0000000-0000-4000-8000-000000000005', 'omar@tab.local', 'Omar'),
  ('a0000000-0000-4000-8000-000000000006', 'ana@tab.local', 'Ana'),
  ('a0000000-0000-4000-8000-000000000007', 'leo@tab.local', 'Leo'),
  ('a0000000-0000-4000-8000-000000000008', 'tomo@tab.local', 'Tomo')
) as u(id, email, name);

-- The signed-in user gets a real-looking name.
update public.profiles set display_name = 'Tara' where id = '11111111-1111-1111-1111-111111111111';

-- The seeded trip stays out of the pictures.
update public.trips set deleted_at = now() where id = '44444444-4444-4444-4444-444444444444';

create function pg_temp.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'email', (select email from auth.users where id = p_user))::text, true);
$$;

-- One trip with the signed-in user and the named members, in order.
create function pg_temp.trip(p_trip uuid, p_name text, p_emails text[]) returns void language plpgsql as $$
declare v_email text;
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  perform public.create_trip_with_self(p_trip, gen_random_uuid(), p_name);
  foreach v_email in array p_emails loop
    perform public.add_trip_person_by_email(p_trip, v_email, null, gen_random_uuid());
  end loop;
  -- Each member joins by claiming the row added under their email.
  foreach v_email in array p_emails loop
    perform pg_temp.as_user((select id from auth.users where email = v_email));
    perform public.claim_trip_people_for_current_email();
  end loop;
end $$;

-- An expense paid by one member and split equally between everyone on the trip.
create function pg_temp.spend(p_trip uuid, p_payer_email text, p_amount numeric, p_currency text,
                              p_description text, p_date date, p_category text) returns void language plpgsql as $$
declare
  v_payer public.trip_people;
  v_people uuid[];
begin
  select * into strict v_payer from public.trip_people where trip_id = p_trip and email = p_payer_email;
  select array_agg(id) into v_people from public.trip_people where trip_id = p_trip;
  perform pg_temp.as_user(v_payer.user_id);
  perform public.create_expense_with_payments_and_splits(
    jsonb_build_object('id', gen_random_uuid(), 'trip_id', p_trip, 'amount', p_amount::text, 'currency', p_currency,
      'description', p_description, 'expense_date', p_date::text, 'payment_method', 'card',
      'category_id', (select id from public.categories where is_default and name = p_category)),
    jsonb_build_array(jsonb_build_object('trip_person_id', v_payer.id, 'amount_paid', p_amount::text, 'payment_mode', 'equal')),
    (select jsonb_agg(jsonb_build_object('trip_person_id', pid, 'amount_owed', (p_amount / array_length(v_people, 1))::text, 'split_type', 'equal'))
     from unnest(v_people) pid));
end $$;

select pg_temp.trip('b0000000-0000-4000-8000-000000000003', 'Japan Ski Cabin',
  array['ana@tab.local', 'leo@tab.local', 'maya@tab.local', 'tomo@tab.local']);
select pg_temp.spend('b0000000-0000-4000-8000-000000000003', 'tomo@tab.local', 96000, 'JPY', 'Cabin, three nights', '2026-02-12', 'Lodging');
select pg_temp.spend('b0000000-0000-4000-8000-000000000003', 'mock@tab.local', 58500, 'JPY', 'Lift passes', '2026-02-13', 'Activities');
select pg_temp.spend('b0000000-0000-4000-8000-000000000003', 'mock@tab.local', 27000, 'JPY', 'Ski rental', '2026-02-13', 'Activities');
select pg_temp.spend('b0000000-0000-4000-8000-000000000003', 'leo@tab.local', 7400, 'JPY', 'Ramen in Hakuba', '2026-02-14', 'Food & Drink');
select pg_temp.spend('b0000000-0000-4000-8000-000000000003', 'ana@tab.local', 6000, 'JPY', 'Onsen', '2026-02-14', 'Activities');

select pg_temp.trip('b0000000-0000-4000-8000-000000000002', 'Flat 23', array['jess@tab.local', 'omar@tab.local']);
select pg_temp.spend('b0000000-0000-4000-8000-000000000002', 'mock@tab.local', 33.00, 'GBP', 'Broadband', '2026-11-02', 'Other');
select pg_temp.spend('b0000000-0000-4000-8000-000000000002', 'jess@tab.local', 61.50, 'GBP', 'Electricity', '2026-11-04', 'Other');
select pg_temp.spend('b0000000-0000-4000-8000-000000000002', 'omar@tab.local', 14.70, 'GBP', 'Cleaning supplies', '2026-11-07', 'Shopping');
select pg_temp.spend('b0000000-0000-4000-8000-000000000002', 'jess@tab.local', 46.20, 'GBP', 'Weekly shop', '2026-11-08', 'Food & Drink');

select pg_temp.trip('b0000000-0000-4000-8000-000000000001', 'Lisbon Long Weekend',
  array['dan@tab.local', 'maya@tab.local', 'priya@tab.local']);
select pg_temp.spend('b0000000-0000-4000-8000-000000000001', 'mock@tab.local', 420.00, 'EUR', 'Airbnb in Alfama', '2026-11-06', 'Lodging');
select pg_temp.spend('b0000000-0000-4000-8000-000000000001', 'priya@tab.local', 32.00, 'EUR', 'Airport taxi', '2026-11-06', 'Transport');
select pg_temp.spend('b0000000-0000-4000-8000-000000000001', 'mock@tab.local', 140.00, 'EUR', 'Surf lesson, Caparica', '2026-11-07', 'Activities');
select pg_temp.spend('b0000000-0000-4000-8000-000000000001', 'dan@tab.local', 96.40, 'EUR', 'Dinner in Bairro Alto', '2026-11-07', 'Food & Drink');
select pg_temp.spend('b0000000-0000-4000-8000-000000000001', 'maya@tab.local', 25.20, 'EUR', 'Tram 28 day passes', '2026-11-08', 'Transport');
select pg_temp.spend('b0000000-0000-4000-8000-000000000001', 'priya@tab.local', 12.80, 'EUR', 'Pastéis de Belém', '2026-11-08', 'Food & Drink');

-- Dan pays some of it back.
select pg_temp.as_user('a0000000-0000-4000-8000-000000000001');
insert into public.settlements (trip_id, from_person_id, to_person_id, amount, currency, settled_at, created_by)
select t.id, d.id, me.id, 60.00, 'EUR', '2026-11-08T17:30:00Z', d.user_id
from public.trips t
join public.trip_people d on d.trip_id = t.id and d.email = 'dan@tab.local'
join public.trip_people me on me.trip_id = t.id and me.email = 'mock@tab.local'
where t.id = 'b0000000-0000-4000-8000-000000000001';

-- The feed shows what the others did: no setup events, nothing by the signed-in user.
delete from public.activity_log
where actor_id = '11111111-1111-1111-1111-111111111111' or action in ('member_joined', 'trip_created');

-- Spread the feed over the last day instead of one minute. The feed hides
-- anything from before a member joined, so the joins move back too.
update public.trip_people set joined_at = now() - interval '3 days'
where trip_id in ('b0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000003');

with ordered as (
  select id, row_number() over (order by "timestamp" desc, id) as n from public.activity_log
)
update public.activity_log a
set "timestamp" = now() - (ordered.n * interval '53 minutes')
from ordered
where ordered.id = a.id;

commit;
