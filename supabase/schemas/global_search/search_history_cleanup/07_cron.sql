-- Scheduled cleanup for the search_history_cleanup module (CA-597).
--
-- Enables pg_cron and registers a daily job that purges orphaned rows from
-- the two search-history tables via public.purge_orphaned_search_history().
--
-- Note: pg_cron objects live in the `cron` schema, which `supabase db diff`
-- does not track. The statements below are the authoritative source and are
-- carried into the generated migration by hand (see the migration header).

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Idempotent (re)registration: unschedule any existing job with this name
-- before scheduling, so re-applying this file never errors or duplicates.
SELECT cron.unschedule('purge-orphaned-search-history')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'purge-orphaned-search-history'
);

-- Daily at 03:00 UTC (low-traffic window).
SELECT cron.schedule(
  'purge-orphaned-search-history',
  '0 3 * * *',
  $$SELECT public.purge_orphaned_search_history();$$
);
