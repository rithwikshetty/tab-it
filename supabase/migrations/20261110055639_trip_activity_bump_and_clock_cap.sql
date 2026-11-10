-- Forward-only: replaces the body of public.set_sync_fields(). No table,
-- column, index, policy, trigger, grant or data changes. CREATE OR REPLACE
-- keeps the function's owner and privileges.
--
-- 1. A trips update that changes only last_activity_at keeps the trip's
--    updated_at and write_id. touch_trip_last_activity() makes that update on
--    every expense and settlement write; restamping the trip made a rename
--    stamped earlier on a phone lose last-write-wins and get dropped.
-- 2. Client-supplied updated_at and deleted_at are capped at
--    clock_timestamp() + 5 minutes, so a phone whose clock runs ahead cannot
--    outrank every later edit of the rows it touched. Values already stored
--    are not changed.

create or replace function public.set_sync_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_deleted timestamptz;
  v_new_deleted timestamptz;
  v_latest      timestamptz := clock_timestamp() + interval '5 minutes';
begin
  v_new_deleted := nullif(to_jsonb(new) ->> 'deleted_at', '')::timestamptz;

  if tg_op = 'INSERT' then
    new.created_at := clock_timestamp();
    if new.updated_at is null then new.updated_at := clock_timestamp(); end if;
    if new.write_id   is null then new.write_id   := gen_random_uuid();  end if;
    if new.updated_at > v_latest then new.updated_at := v_latest; end if;
    -- Only tables with a deleted_at column reach this assignment.
    if v_new_deleted > v_latest then new.deleted_at := v_latest; end if;
    return new;
  end if;

  if tg_table_name = 'trips'
     and (to_jsonb(new) - 'last_activity_at') = (to_jsonb(old) - 'last_activity_at')
     and (to_jsonb(new) -> 'last_activity_at') is distinct from (to_jsonb(old) -> 'last_activity_at') then
    return new;
  end if;

  v_old_deleted := nullif(to_jsonb(old) ->> 'deleted_at', '')::timestamptz;

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
  if new.updated_at > v_latest then
    new.updated_at := v_latest;
  end if;
  if v_new_deleted > v_latest
     and v_new_deleted is distinct from v_old_deleted then
    new.deleted_at := v_latest;
    v_new_deleted  := v_latest;
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
  'BEFORE INSERT/UPDATE trigger for synced tables. Stamps created_at on insert and fills missing updated_at/write_id. On update, delete-wins is unconditional across live/deleted state (live-to-deleted writes apply; resurrection is blocked); live-live writes use updated_at LWW and both-deleted writes use deleted_at LWW, with write_id tiebreakers. Metadata-less updates get fresh server stamps. Client updated_at and deleted_at are capped at clock_timestamp() + 5 minutes. A trips update that changes only last_activity_at keeps updated_at and write_id.';
