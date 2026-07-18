-- 1. Extensions + shared trigger functions
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap     with schema extensions;

grant usage on schema extensions to public;

set check_function_bodies = off;

-- Sync-field stamping + last-write-wins enforcement, shared by every synced
-- table. Clients send updated_at + write_id with each push; the policy is
-- LWW with delete-wins and a write_id tiebreaker (mirrors TabCore's
-- ConflictResolver). Writes that do not touch the metadata (server-side
-- maintenance, triggers, legacy paths) keep the old stamp-fresh behavior.
-- deleted_at is read via jsonb because not every synced table has the column.
create or replace function public.set_sync_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_deleted timestamptz;
  v_new_deleted timestamptz;
begin
  if tg_op = 'INSERT' then
    new.created_at := clock_timestamp();
    if new.updated_at is null then new.updated_at := clock_timestamp(); end if;
    if new.write_id   is null then new.write_id   := gen_random_uuid();  end if;
    return new;
  end if;

  v_old_deleted := nullif(to_jsonb(old) ->> 'deleted_at', '')::timestamptz;
  v_new_deleted := nullif(to_jsonb(new) ->> 'deleted_at', '')::timestamptz;

  -- Delete-wins: a tombstoned row is never resurrected by a live update.
  if v_old_deleted is not null and v_new_deleted is null then
    return null;
  end if;

  if new.write_id is not distinct from old.write_id then
    -- Metadata-less write: stamp fresh server values (previous behavior).
    new.updated_at := clock_timestamp();
    new.write_id   := gen_random_uuid();
    return new;
  end if;

  -- Client-supplied metadata: last write wins, write_id breaks ties. A write
  -- whose updated_at equals the row's goes to the tiebreaker — clients always
  -- send write_id and updated_at together.
  if new.updated_at is null then
    new.updated_at := clock_timestamp();
  end if;

  if v_old_deleted is not null and v_new_deleted is not null then
    if v_new_deleted < v_old_deleted
       or (v_new_deleted = v_old_deleted and new.write_id::text < old.write_id::text) then
      return null;
    end if;
  elsif v_old_deleted is null and v_new_deleted is null then
    if new.updated_at < old.updated_at
       or (new.updated_at = old.updated_at and new.write_id::text < old.write_id::text) then
      return null;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.set_sync_fields() is
  'BEFORE INSERT/UPDATE trigger for synced tables. Stamps created_at on insert and fills missing updated_at/write_id. On update, delete-wins is unconditional across live/deleted state (live-to-deleted writes apply; resurrection is blocked); live-live writes use updated_at LWW and both-deleted writes use deleted_at LWW, with write_id tiebreakers. Metadata-less updates get fresh server stamps.';


-- ============================================================================
