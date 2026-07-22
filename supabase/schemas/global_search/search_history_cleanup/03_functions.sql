-- Functions for the search_history_cleanup module (CA-597).
--
-- Purges orphaned rows from the two search-history tables. Both tables store
-- auth.uid() in user_id with NO foreign key to auth.users (cross-schema
-- boundary), so rows are not cascade-deleted when a user is removed from
-- Supabase Auth. This function reclaims those orphaned rows; a pg_cron job
-- (see 07_cron.sql) invokes it on a daily schedule.

-- ============================================================
-- purge_orphaned_search_history()
--
-- Deletes rows in search_history and project_search_history whose user_id
-- no longer exists in auth.users. Rows belonging to active users are never
-- touched.
--
-- SECURITY DEFINER: required to (a) read auth.users, which the cron role
-- cannot see under normal privileges, and (b) bypass the per-user RLS
-- policies on both tables (each restricts DELETE to user_id = auth.uid()).
--
-- This function is not reachable via PostgREST: EXECUTE is revoked from all
-- Data API roles (anon/authenticated/service_role) below and granted only to
-- the postgres role that pg_cron runs as. (The CLI's auto_expose_new_tables
-- pass may re-grant the Data API roles on db reset — CA-729; the in-body JWT
-- guard covers that case.)
-- ============================================================
CREATE OR REPLACE FUNCTION public.purge_orphaned_search_history()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Defense-in-depth against an authenticated Data API call. Primary access
  -- control is the REVOKE below (no Data API role holds EXECUTE); this
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

-- Lock down execution: only the postgres role (which pg_cron runs as) may
-- invoke this. Revoke the default PUBLIC grant and the Data API roles.
REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM anon;
REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.purge_orphaned_search_history() FROM service_role;
GRANT EXECUTE ON FUNCTION public.purge_orphaned_search_history() TO postgres;
