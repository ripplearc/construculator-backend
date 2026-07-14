-- CA-597: Purge orphaned search-history rows.
-- search_history.user_id and project_search_history.user_id store auth.uid()
-- with no FK to auth.users (cross-schema boundary), so rows are not
-- cascade-deleted when a user is removed from Supabase Auth. This adds a
-- SECURITY DEFINER purge function and a daily pg_cron job that deletes rows
-- whose user_id no longer exists in auth.users, from both tables.
-- https://ripplearc.youtrack.cloud/issue/CA-597
--
-- Hand-authored (not `supabase db diff`-generated): pg_cron objects live in
-- the `cron` schema, which `db diff` does not track. The executable
-- statements below mirror supabase/schemas/global_search/
-- search_history_cleanup/ (03_functions.sql + 07_cron.sql), which remain
-- the source of truth; only migration boilerplate (check_function_bodies)
-- and some explanatory comments differ.
-- (Annotated per the CA-737 precedent for annotated migrations.)

set check_function_bodies = off;

-- ============================================================
-- Purge function (see search_history_cleanup/03_functions.sql).
-- ============================================================
CREATE OR REPLACE FUNCTION public.purge_orphaned_search_history()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Defense-in-depth against an authenticated Data API call. Primary access
  -- control is the REVOKE below (anon/authenticated hold no EXECUTE); this
  -- guard is a second layer in case the CLI's auto_expose_new_tables grant
  -- pass re-grants EXECUTE on db reset (a repo-wide issue tracked by CA-729,
  -- affecting every function). PostgREST populates request.jwt.claims with a
  -- non-empty JWT for an authenticated request; pg_cron and direct
  -- service/psql calls never set it. This is a maintenance function that
  -- bypasses RLS and deletes rows.
  --
  -- Scope note: this does not by itself stop an *anon* call (no JWT, so it
  -- looks like the cron path) — that path is closed only by the REVOKE, same
  -- as every other SECURITY DEFINER function in this schema.
  IF current_setting('request.jwt.claims', true) IS NOT NULL
     AND current_setting('request.jwt.claims', true) <> '' THEN
    RAISE EXCEPTION 'purge_orphaned_search_history is not callable via the API'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.search_history sh
  WHERE NOT EXISTS (
    SELECT 1 FROM auth.users u WHERE u.id = sh.user_id
  );

  DELETE FROM public.project_search_history psh
  WHERE NOT EXISTS (
    SELECT 1 FROM auth.users u WHERE u.id = psh.user_id
  );
END;
$$;

COMMENT ON FUNCTION public.purge_orphaned_search_history IS
'Deletes search_history and project_search_history rows whose user_id no
longer exists in auth.users. SECURITY DEFINER; invoked by the daily
purge-orphaned-search-history pg_cron job (CA-597). Not exposed via the API.';

REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM anon;
REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purge_orphaned_search_history() TO postgres;

-- ============================================================
-- pg_cron schedule (see search_history_cleanup/07_cron.sql).
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('purge-orphaned-search-history')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'purge-orphaned-search-history'
);

SELECT cron.schedule(
  'purge-orphaned-search-history',
  '0 3 * * *',
  $$SELECT public.purge_orphaned_search_history();$$
);
