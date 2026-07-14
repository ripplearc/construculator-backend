-- Functions for the search_history module.
-- Includes trigger functions and the get_search_suggestions RPC.
--
-- Note: public.global_search is NOT defined here. Its canonical
-- definition lives in ../global_search/03_functions.sql — a stale
-- pre-CA-752 copy used to live in this file and was removed in CA-737
-- so the declarative schema dir has exactly one definition per function.

-- ============================================================
-- Trigger function: increment search_count on repeat searches.
-- ============================================================
CREATE OR REPLACE FUNCTION public.increment_search_count()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  NEW.search_count := OLD.search_count + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Trigger function: maintain updated_at on every row change.
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_search_history_updated_at()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- get_search_suggestions RPC
--
-- Accepts: user_id uuid — must match auth.uid() (validated at entry).
--   Caller must pass their own auth UID; the guard rejects any other UUID.
-- Returns: text[]
--
-- Three-step priority logic:
--
-- Step 1 — Personal History:
--   Query search_history for auth.uid() where has_results = true.
--   Order by search_count DESC, limit 10. Return immediately if found.
--
-- Step 2 — Teammate History:
--   If Step 1 returns nothing, query search_history where project_id
--   is in the projects auth.uid() belongs to, user_id != auth.uid(),
--   and has_results = true. Deduplicate (DISTINCT ON), order by highest
--   search_count DESC, limit 10. Return immediately if found.
--
-- Step 3: Return empty array.
--
-- SECURITY INVOKER: RLS on search_history enforces visibility.
-- The "search_history_teammate_select_policy" grants access to
-- shared-project rows required for Step 2.
--
-- Note: search_history.user_id stores auth.uid() (= users.credential_id).
--       project_members.user_id stores users.id (internal UUID).
--       The join bridges these via the users table.
--
-- has_results contract:
--   search_history.has_results defaults to false on insert.
--   The caller is responsible for upserting again with has_results = true
--   after confirming the search returned at least one result. Rows with
--   has_results = false are stored in history but excluded from suggestions.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_search_suggestions(user_id uuid)
RETURNS text[]
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_suggestions text[];
BEGIN

  -- Anti-spoof guard: reject calls where the passed user_id does not
  -- match the authenticated session. Prevents parameter spoofing via
  -- the PostgREST API even though RLS would silently return empty rows.
  IF user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: user_id must match the authenticated session'
      USING ERRCODE = '42501';
  END IF;

  -- Step 1: Personal history — own searches that returned results
  SELECT ARRAY(
    SELECT sh.search_term
    FROM search_history sh
    WHERE sh.user_id = auth.uid()
      AND sh.has_results = true
    ORDER BY sh.search_count DESC
    LIMIT 10
  ) INTO v_suggestions;

  IF cardinality(v_suggestions) > 0 THEN
    RETURN v_suggestions;
  END IF;

  -- Step 2: Teammate history — top terms from users sharing a project.
  -- DISTINCT ON picks one row per term (the one with highest search_count).
  -- The outer ORDER BY then sorts those representatives by count DESC.
  SELECT ARRAY(
    SELECT t.search_term
    FROM (
      SELECT DISTINCT ON (sh.search_term)
        sh.search_term,
        sh.search_count
      FROM search_history sh
      WHERE sh.project_id IN (
          SELECT pm.project_id
          FROM project_members pm
          JOIN users u ON pm.user_id = u.id
          WHERE u.credential_id = auth.uid()
            AND pm.membership_status = 'joined'
        )
        AND sh.user_id != auth.uid()
        AND sh.has_results = true
      ORDER BY sh.search_term, sh.search_count DESC
    ) t
    ORDER BY t.search_count DESC
    LIMIT 10
  ) INTO v_suggestions;

  IF cardinality(v_suggestions) > 0 THEN
    RETURN v_suggestions;
  END IF;

  -- Step 3: Nothing found — return empty array
  RETURN ARRAY[]::text[];

END;
$$;

COMMENT ON FUNCTION public.get_search_suggestions IS
'Returns up to 10 search term suggestions.
Accepts user_id uuid — must match auth.uid() or raises 42501 Unauthorized.
Step 1: calling user own history (has_results=true), by frequency.
Step 2: teammate history from shared projects (has_results=true), deduplicated, by frequency.
Step 3: empty array.
has_results contract: caller must upsert with has_results=true after a non-empty result set.
Rows with has_results=false are stored but excluded from suggestions.';
