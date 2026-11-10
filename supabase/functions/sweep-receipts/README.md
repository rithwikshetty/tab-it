# sweep-receipts edge function

Removes receipt photos that no expense points at. Invoked once a day by the
`sweep-receipts` pg_cron job through `private.request_receipt_sweep()` and
`pg_net` (see `supabase/sql/22_receipt_sweep.sql`).

Flow: cron job → `pg_net` POST (with `x-webhook-secret`) → this function →
`orphaned_receipt_objects()` (up to 500 names) → Storage API `remove`, 100 at
a time. The response is `{"found": n, "removed": n}`.

The Storage API is the only way to delete a file. `storage.objects` refuses a
direct SQL delete, and the storage policies let a client delete an object only
while a live expense still points at it.

## What counts as orphaned

An object in the `receipts` bucket is listed when all of these hold:

- its name is a receipt path (`<trip_id>/<expense_id>.jpg`, with or without a
  leading `receipts/`);
- no live expense has it as `receipt_storage_path`;
- the expense named in the path, if it still exists, was last changed more
  than 30 days ago;
- the object was created and last written more than 30 days ago.

The 30 days cover a phone that was offline. It can push a copy of the expense
that still names the photo, and under last-write-wins that copy can win.

## Secrets

Auto-injected by Supabase: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.

`WEBHOOK_SECRET` is the secret `send-push` uses. It must equal
`private.app_config.push_webhook_secret`.

## DB wiring

```sql
insert into private.app_config (key, value) values
  ('receipt_sweep_url', 'https://<project-ref>.supabase.co/functions/v1/sweep-receipts')
on conflict (key) do update set value = excluded.value;
```

To stop the sweep: `delete from private.app_config where key = 'receipt_sweep_url';`

To see what the next run would remove, as the service role:
`select name from public.orphaned_receipt_objects();`

## Deploy

```bash
supabase functions deploy sweep-receipts --no-verify-jwt
```

`--no-verify-jwt` is required: the call comes from the database with no user
JWT and is authenticated by `x-webhook-secret` instead.
