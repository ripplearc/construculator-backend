BEGIN;

-- Tests for CA-597: public.purge_orphaned_search_history() deletes rows in
-- search_history and project_search_history whose user_id no longer exists in
-- auth.users, while leaving rows of active users untouched.

SELECT plan(7);

SELECT has_function(
  'public',
  'purge_orphaned_search_history',
  ARRAY[]::text[],
  'purge_orphaned_search_history() exists with no arguments'
);

-- The pg_cron job registered. The cron schema is not tracked by
-- `supabase db diff`, so this is the only automated check of the wiring.
SELECT is(
  (SELECT count(*)::int FROM cron.job
   WHERE jobname = 'purge-orphaned-search-history'),
  1,
  'pg_cron job purge-orphaned-search-history is registered'
);

-- API guard: a call carrying a JWT-claims setting (as PostgREST always sends)
-- is rejected, even if EXECUTE was re-granted to authenticated on db reset.
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
SELECT throws_ok(
  $$ SELECT public.purge_orphaned_search_history() $$,
  '42501',
  'purge_orphaned_search_history is not callable via the API',
  'Call with request.jwt.claims set (Data API path) is rejected'
);
SELECT set_config('request.jwt.claims', NULL, true);

DO $$
DECLARE
  v_active_user uuid := '11111111-1111-1111-1111-111111111111';
  v_orphan_user uuid := '99999999-9999-9999-9999-999999999999';
BEGIN
  -- One active user exists in auth; the orphan user_id never does.
  INSERT INTO auth.users (id) VALUES (v_active_user);

  -- Global Search history: one active row, one orphan row.
  INSERT INTO public.search_history (user_id, search_term, scope, has_results)
    VALUES (v_active_user, 'active term', 'dashboard', true);
  INSERT INTO public.search_history (user_id, search_term, scope, has_results)
    VALUES (v_orphan_user, 'orphan term', 'dashboard', true);

  -- Project Search history: one active row, one orphan row.
  INSERT INTO public.project_search_history (user_id, search_term, has_results)
    VALUES (v_active_user, 'active project term', true);
  INSERT INTO public.project_search_history (user_id, search_term, has_results)
    VALUES (v_orphan_user, 'orphan project term', true);
END $$;

-- Run the purge.
SELECT public.purge_orphaned_search_history();

-- search_history: orphan gone, active preserved.
SELECT is(
  (SELECT count(*)::int FROM public.search_history
   WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  0,
  'search_history: orphan rows are purged'
);

SELECT is(
  (SELECT count(*)::int FROM public.search_history
   WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'search_history: active user rows are untouched'
);

-- project_search_history: orphan gone, active preserved.
SELECT is(
  (SELECT count(*)::int FROM public.project_search_history
   WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  0,
  'project_search_history: orphan rows are purged'
);

SELECT is(
  (SELECT count(*)::int FROM public.project_search_history
   WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'project_search_history: active user rows are untouched'
);

SELECT * FROM finish();

ROLLBACK;
