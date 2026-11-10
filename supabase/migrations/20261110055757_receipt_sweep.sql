-- Forward-only: adds the daily receipt sweep. Enables pg_cron, adds
-- public.orphaned_receipt_objects(integer, timestamptz) and
-- private.request_receipt_sweep(), and schedules the sweep-receipts job.
-- No table, column, policy or existing function changes. The job does nothing
-- until private.app_config holds receipt_sweep_url.

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
