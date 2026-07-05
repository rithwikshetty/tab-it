-- 2. private schema + helpers
-- ============================================================================
-- The `private` schema holds RLS helper functions. Postgres RLS can call
-- across schemas, but PostgREST does NOT expose /rest/v1/rpc for anything
-- outside the configured exposed schemas (default: public) — so functions
-- here are invisible as RPC endpoints while remaining usable from RLS.

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.normalized_email(p_email text)
returns text
language sql
immutable
set search_path = public, private
as $$
  select lower(trim(p_email));
$$;

comment on function private.normalized_email(text) is
  'Canonical email form for trip-person matching: lowercase + trim.';

create or replace function private.current_auth_email()
returns text
language sql
security definer
stable
set search_path = public, private
as $$
  select private.normalized_email(email)
  from auth.users
  where id = auth.uid();
$$;

comment on function private.current_auth_email() is
  'Returns auth.uid() email in canonical form. SECURITY DEFINER because auth.users is private to Supabase.';

create or replace function private.is_profile_trip_member(p_trip_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1 from public.trip_people tp
    where tp.trip_id = p_trip_id
      and tp.user_id = p_user_id
      and tp.joined_at is not null
      and tp.removed_at is null
  );
$$;

comment on function private.is_profile_trip_member(uuid, uuid) is
  'True if the supplied auth profile has a claimed, non-removed person row in the supplied trip. Gates all trip access. SECURITY DEFINER to bypass RLS on trip_people.';

create or replace function private.is_profile_trip_member_any(p_trip_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1 from public.trip_people tp
    where tp.trip_id = p_trip_id
      and tp.user_id = p_user_id
      and tp.joined_at is not null
  );
$$;

comment on function private.is_profile_trip_member_any(uuid, uuid) is
  'True if the supplied auth profile ever claimed a person row in the supplied trip, removed or not. For validating creator/editor identity columns on ledger rows authored by since-removed members — never for access checks.';

create or replace function private.is_trip_member(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select private.is_profile_trip_member(p_trip_id, auth.uid());
$$;

comment on function private.is_trip_member(uuid) is
  'True if auth.uid() has a joined trip_people row for the given trip. Used by every RLS policy that scopes to trip access. SECURITY DEFINER to bypass self-recursion.';

create or replace function private.is_trip_person(p_trip_id uuid, p_person_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1 from public.trip_people tp
    where tp.id = p_person_id
      and tp.trip_id = p_trip_id
  );
$$;

comment on function private.is_trip_person(uuid, uuid) is
  'True if the supplied trip_people.id belongs to the supplied trip.';

create or replace function private.receipt_object_trip_id(p_name text)
returns uuid
language plpgsql
security definer
immutable
set search_path = public, private
as $$
declare
  first_token text;
  second_token text;
  candidate text;
begin
  first_token := split_part(p_name, '/', 1);
  second_token := split_part(p_name, '/', 2);
  candidate := case when first_token = 'receipts' then second_token else first_token end;

  if candidate ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return candidate::uuid;
  end if;

  return null;
end;
$$;

comment on function private.receipt_object_trip_id(text) is
  'Extracts a trip UUID from receipt object paths. Supports both <trip_id>/<expense_id>.jpg and receipts/<trip_id>/<expense_id>.jpg.';

create or replace function private.receipt_object_expense_id(p_name text)
returns uuid
language plpgsql
security definer
immutable
set search_path = public, private
as $$
declare
  first_token text;
  second_token text;
  third_token text;
  candidate text;
begin
  first_token := split_part(p_name, '/', 1);
  second_token := split_part(p_name, '/', 2);
  third_token := split_part(p_name, '/', 3);
  candidate := case when first_token = 'receipts' then third_token else second_token end;
  candidate := regexp_replace(candidate, '\.[^.\/]+$', '');

  if candidate ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return candidate::uuid;
  end if;

  return null;
end;
$$;

comment on function private.receipt_object_expense_id(text) is
  'Extracts an expense UUID from receipt object paths. Supports both <trip_id>/<expense_id>.jpg and receipts/<trip_id>/<expense_id>.jpg.';

create or replace function private.can_read_receipt_object(p_name text)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1
    from public.expenses e
    where e.id = private.receipt_object_expense_id(p_name)
      and e.trip_id = private.receipt_object_trip_id(p_name)
      and e.deleted_at is null
      and e.receipt_storage_path = p_name
      and private.is_trip_member(e.trip_id)
  );
$$;

comment on function private.can_read_receipt_object(text) is
  'True when the receipt object path belongs to a live expense in a trip the current user can read.';

create or replace function private.can_write_receipt_object(p_name text)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1
    from public.expenses e
    where e.id = private.receipt_object_expense_id(p_name)
      and e.trip_id = private.receipt_object_trip_id(p_name)
      and e.deleted_at is null
      and e.receipt_storage_path = p_name
      and e.created_by = auth.uid()
      and private.is_trip_member(e.trip_id)
  );
$$;

comment on function private.can_write_receipt_object(text) is
  'True when the receipt object path belongs to a live expense created by the current user.';


-- ============================================================================
