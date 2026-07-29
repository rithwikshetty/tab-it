-- Synthetic development data for the disposable local Supabase stack.
-- Every identity and ledger entry below is fictional. Never replace this file
-- with a dump or copy of production data.

set search_path = extensions, public, pg_temp;

insert into auth.users (
  id,
  email,
  instance_id,
  aud,
  role,
  encrypted_password,
  email_confirmed_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'mock@tab.local',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    crypt('local-only-password', gen_salt('bf')),
    '2026-07-20T08:00:00Z',
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Test User"}',
    '2026-07-20T08:00:00Z',
    '2026-07-20T08:00:00Z'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'alex@tab.local',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    crypt('local-only-password', gen_salt('bf')),
    '2026-07-20T08:00:00Z',
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Alex"}',
    '2026-07-20T08:00:00Z',
    '2026-07-20T08:00:00Z'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'sam@tab.local',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    crypt('local-only-password', gen_salt('bf')),
    '2026-07-20T08:00:00Z',
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Sam"}',
    '2026-07-20T08:00:00Z',
    '2026-07-20T08:00:00Z'
  );

insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  id::text,
  id,
  jsonb_build_object(
    'sub', id::text,
    'email', email,
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  '2026-07-20T08:00:00Z',
  '2026-07-20T08:00:00Z',
  '2026-07-20T08:00:00Z'
from auth.users
where email in ('mock@tab.local', 'alex@tab.local', 'sam@tab.local');

insert into public.trips (id, name, created_by, last_activity_at)
values (
  '44444444-4444-4444-4444-444444444444',
  'Lake District',
  '11111111-1111-1111-1111-111111111111',
  '2026-07-29T10:00:00Z'
);

insert into public.trip_people (
  id,
  trip_id,
  user_id,
  email,
  display_name,
  invited_by,
  joined_at
)
values
  (
    '61111111-1111-1111-1111-111111111111',
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111',
    'mock@tab.local',
    'Test User',
    '11111111-1111-1111-1111-111111111111',
    '2026-07-20T09:00:00Z'
  ),
  (
    '62222222-2222-2222-2222-222222222222',
    '44444444-4444-4444-4444-444444444444',
    '22222222-2222-2222-2222-222222222222',
    'alex@tab.local',
    'Alex',
    '11111111-1111-1111-1111-111111111111',
    '2026-07-20T09:05:00Z'
  ),
  (
    '63333333-3333-3333-3333-333333333333',
    '44444444-4444-4444-4444-444444444444',
    '33333333-3333-3333-3333-333333333333',
    'sam@tab.local',
    'Sam',
    '11111111-1111-1111-1111-111111111111',
    '2026-07-20T09:10:00Z'
  ),
  (
    '64444444-4444-4444-4444-444444444444',
    '44444444-4444-4444-4444-444444444444',
    null,
    'jordan@tab.local',
    'Jordan',
    '11111111-1111-1111-1111-111111111111',
    null
  );

insert into public.categories (id, trip_id, name, icon, is_default)
values (
  '70000000-0000-0000-0000-000000000001',
  '44444444-4444-4444-4444-444444444444',
  'Supplies',
  'backpack',
  false
);

insert into public.expenses (
  id,
  trip_id,
  amount,
  currency,
  category_id,
  description,
  expense_date,
  payment_method,
  created_by,
  created_at,
  updated_at
)
values
  (
    '81111111-1111-1111-1111-111111111111',
    '44444444-4444-4444-4444-444444444444',
    72.00,
    'GBP',
    '00000001-0000-0000-0000-000000000000',
    'Weekend groceries',
    '2026-07-25',
    'card',
    '11111111-1111-1111-1111-111111111111',
    '2026-07-25T15:00:00Z',
    '2026-07-25T15:00:00Z'
  ),
  (
    '82222222-2222-2222-2222-222222222222',
    '44444444-4444-4444-4444-444444444444',
    45.00,
    'GBP',
    '00000002-0000-0000-0000-000000000000',
    'Train tickets',
    '2026-07-26',
    'card',
    '22222222-2222-2222-2222-222222222222',
    '2026-07-26T08:00:00Z',
    '2026-07-26T08:00:00Z'
  ),
  (
    '83333333-3333-3333-3333-333333333333',
    '44444444-4444-4444-4444-444444444444',
    60.00,
    'EUR',
    '00000004-0000-0000-0000-000000000000',
    'Museum tickets',
    '2026-07-27',
    'cash',
    '33333333-3333-3333-3333-333333333333',
    '2026-07-27T11:00:00Z',
    '2026-07-27T11:00:00Z'
  );

insert into public.expense_payments (
  expense_id,
  trip_person_id,
  amount_paid,
  payment_mode
)
values
  ('81111111-1111-1111-1111-111111111111', '61111111-1111-1111-1111-111111111111', 72.00, 'exact'),
  ('82222222-2222-2222-2222-222222222222', '62222222-2222-2222-2222-222222222222', 45.00, 'exact'),
  ('83333333-3333-3333-3333-333333333333', '63333333-3333-3333-3333-333333333333', 60.00, 'exact');

insert into public.expense_splits (
  expense_id,
  trip_person_id,
  amount_owed,
  split_type
)
values
  ('81111111-1111-1111-1111-111111111111', '61111111-1111-1111-1111-111111111111', 24.00, 'equal'),
  ('81111111-1111-1111-1111-111111111111', '62222222-2222-2222-2222-222222222222', 24.00, 'equal'),
  ('81111111-1111-1111-1111-111111111111', '63333333-3333-3333-3333-333333333333', 24.00, 'equal'),
  ('82222222-2222-2222-2222-222222222222', '61111111-1111-1111-1111-111111111111', 15.00, 'equal'),
  ('82222222-2222-2222-2222-222222222222', '62222222-2222-2222-2222-222222222222', 15.00, 'equal'),
  ('82222222-2222-2222-2222-222222222222', '63333333-3333-3333-3333-333333333333', 15.00, 'equal'),
  ('83333333-3333-3333-3333-333333333333', '61111111-1111-1111-1111-111111111111', 20.00, 'equal'),
  ('83333333-3333-3333-3333-333333333333', '62222222-2222-2222-2222-222222222222', 20.00, 'equal'),
  ('83333333-3333-3333-3333-333333333333', '63333333-3333-3333-3333-333333333333', 20.00, 'equal');

insert into public.settlements (
  id,
  trip_id,
  from_person_id,
  to_person_id,
  amount,
  currency,
  note,
  settled_at,
  created_by
)
values (
  '91111111-1111-1111-1111-111111111111',
  '44444444-4444-4444-4444-444444444444',
  '61111111-1111-1111-1111-111111111111',
  '62222222-2222-2222-2222-222222222222',
  10.00,
  'GBP',
  'Partial repayment',
  '2026-07-28T18:00:00Z',
  '11111111-1111-1111-1111-111111111111'
);
