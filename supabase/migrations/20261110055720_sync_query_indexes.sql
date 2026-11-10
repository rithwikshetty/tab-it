-- Forward-only: adds two indexes. No other change. Both tables are small, so
-- a plain CREATE INDEX (brief write lock) is used rather than CONCURRENTLY,
-- which cannot run inside a migration transaction.
--
-- activity_log_timestamp_idx serves the clients' feed pull:
--   where timestamp >= cutoff order by timestamp desc limit 300
-- trip_people_pending_email_idx serves claim_trip_people_for_current_email(),
-- which runs before every full sync:
--   where email = $1 and user_id is null

create index if not exists activity_log_timestamp_idx
  on public.activity_log(timestamp desc);

create index if not exists trip_people_pending_email_idx
  on public.trip_people(email) where user_id is null;
