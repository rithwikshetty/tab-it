# send-push edge function

Sends APNs push notifications for trip activity. Invoked by the
`trg_activity_notify_push` trigger on `public.activity_log` via `pg_net`
(see `supabase/sql/18_notifications_push.sql`).

Flow: `activity_log` INSERT → `pg_net` POST (with `x-webhook-secret`) → this
function → `push_targets_for_activity(activity_id)` (members − actor − muters,
each with their unread badge) → direct APNs over HTTP/2 (token auth, ES256 `.p8`).
Dead tokens (`410` / `Unregistered`) are pruned from `push_devices`.
`BadDeviceToken` is retained and logged as a likely `APNS_ENV` mismatch.

The in-app Activity feed does **not** depend on this function — it reads
`activity_log` through the normal sync. Push is an additive channel.

## Secrets

Auto-injected by Supabase: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.

Set these (Supabase dashboard → Edge Functions → Secrets, or
`supabase secrets set`, or the Management API `POST /v1/projects/{ref}/secrets`):

| Secret | Meaning |
| --- | --- |
| `WEBHOOK_SECRET` | Shared secret; must equal `private.app_config.push_webhook_secret`. |
| `APNS_TEAM_ID` | Apple Developer Team ID (10 chars). |
| `APNS_KEY_ID` | APNs auth key ID (10 chars). |
| `APNS_BUNDLE_ID` | App bundle id, e.g. `com.rithwikshetty.tab`. Used as `apns-topic`. |
| `APNS_P8_KEY` | Full `.p8` contents (`-----BEGIN PRIVATE KEY----- … -----END PRIVATE KEY-----`). |
| `APNS_ENV` | `sandbox` (Xcode/dev builds) or `production` (TestFlight/App Store). |

Until `APNS_TEAM_ID/KEY_ID/BUNDLE_ID/P8_KEY` are all set the function returns
`{"skipped":"apns_not_configured"}` (the pipe stays healthy, just no send).

## DB wiring (already applied on this project)

```sql
insert into private.app_config (key, value) values
  ('push_webhook_url',    'https://<project-ref>.supabase.co/functions/v1/send-push'),
  ('push_webhook_secret', '<same value as WEBHOOK_SECRET>')
on conflict (key) do update set value = excluded.value;
```

To disable push fan-out entirely: `delete from private.app_config where key = 'push_webhook_url';`

## APNs environment

The app ships `aps-environment = development` (Xcode/dev → APNs **sandbox**), so
keep `APNS_ENV=sandbox` for development device builds. For TestFlight/App Store,
the entitlement resolves to `production` at distribution signing — set
`APNS_ENV=production`.

## Status on this project

- `WEBHOOK_SECRET` and `APNS_ENV=sandbox` are set; `app_config` is wired.
- The trigger → `pg_net` → function chain is verified (returns
  `apns_not_configured` until the APNs key is added).
- Remaining to go live: add the four `APNS_*` key secrets and register a real
  device (the Simulator cannot receive real APNs deliveries).

## Deploy

```bash
supabase functions deploy send-push --no-verify-jwt
```

`--no-verify-jwt` is required: the call originates from the DB (no user JWT) and
is authenticated by `x-webhook-secret` instead.
