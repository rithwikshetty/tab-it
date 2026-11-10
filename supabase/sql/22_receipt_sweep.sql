-- 22. Receipt sweep (storage objects no expense points at)
-- ============================================================================
-- Removing a receipt, deleting its expense or purging the row leaves the photo
-- in the `receipts` bucket, where the storage policies let nobody read or
-- delete it. Once a day pg_cron asks the `sweep-receipts` edge function to
-- remove those objects, because storage files are deleted through the Storage
-- API, not from SQL. The function URL lives in private.app_config beside the
-- push webhook and shares its secret. If it is unset, the job does nothing.
--
-- An object waits until neither it nor its expense has changed for 30 days.
-- Under last-write-wins a phone that was offline can push a copy of the
-- expense that still names the photo, and that copy can win.

create extension if not exists pg_cron;

create or replace function public.orphaned_receipt_objects(
  p_limit  integer default 500,
  p_cutoff timestamptz default clock_timestamp() - interval '30 days'
)
returns table (name text)
language sql
security definer
stable
set search_path = public, private
as $$
  select o.name
  from storage.objects o
  where o.bucket_id = 'receipts'
    and private.receipt_object_expense_id(o.name) is not null
    and greatest(o.created_at, o.updated_at) < p_cutoff
    and not exists (
      select 1 from public.expenses e
      where e.receipt_storage_path = o.name
        and e.deleted_at is null
    )
    and not exists (
      select 1 from public.expenses e
      where e.id = private.receipt_object_expense_id(o.name)
        and e.updated_at >= p_cutoff
    )
  order by o.name
  limit p_limit;
$$;

comment on function public.orphaned_receipt_objects(integer, timestamptz) is
  'Receipt objects no live expense points at, where neither the object nor its expense has changed since the cutoff. Called by the sweep-receipts edge function (service role).';

create or replace function private.request_receipt_sweep()
returns void
language plpgsql
security definer
set search_path = private
as $$
declare
  v_url    text := private.config('receipt_sweep_url');
  v_secret text := private.config('push_webhook_secret');
begin
  if v_url is null then
    return;  -- sweep not configured
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', coalesce(v_secret, '')
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

comment on function private.request_receipt_sweep() is
  'Asks the sweep-receipts edge function to remove orphaned receipt objects. Run daily by the sweep-receipts cron job.';

revoke execute on function public.orphaned_receipt_objects(integer, timestamptz) from public, anon, authenticated;
grant  execute on function public.orphaned_receipt_objects(integer, timestamptz) to service_role;
revoke execute on function private.request_receipt_sweep() from public, anon, authenticated;

select cron.schedule('sweep-receipts', '17 3 * * *', 'select private.request_receipt_sweep()');
