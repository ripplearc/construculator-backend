-- Functions for the Project Search feature.
-- Only contains the suggestions RPC. The BEFORE UPDATE trigger functions
-- are reused from the global search_history module:
--   * public.increment_search_count        (sets NEW.search_count := OLD.search_count + 1)
--   * public.set_search_history_updated_at (sets NEW.updated_at := now())
-- Both are table-agnostic and attached in 04_triggers.sql.

-- ============================================================
-- get_project_search_suggestions RPC
--
-- Parameters:
--   user_id uuid — must match auth.uid() (validated at entry).
--     Caller must pass their own auth UID; the guard rejects any other UUID.
-- Returns: text[]
--
-- Two-step priority logic:
--
-- Step 1 — Personal History:
--   Search project_search_history for auth.uid() where has_results = true.
--   Order by search_count DESC, limit 10.
--
-- Step 2 — Empty Array:
--   Return empty array if Step 1 yields nothing.
--
-- Project Search is fully isolated from Global Search; no fallback into
-- search_history or any other table.
--
-- SECURITY INVOKER: RLS on project_search_history enforces visibility
-- (users can only read their own rows).
--
-- Privacy: this function returns only search-term strings. It does NOT
-- select users.credential_id or any other auth identifier. (Prior review
-- caught credential_id leakage on the global search RPC — that mistake
-- must not be repeated here.)
--
-- has_results contract:
--   project_search_history.has_results defaults to false on insert.
--   The caller is responsible for upserting again with has_results = true
--   after confirming the search returned at least one result. Rows with
--   has_results = false are stored in history (and surface in recent
--   searches) but are excluded from suggestions.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_project_search_suggestions(
  user_id uuid
)
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
    SELECT psh.search_term
    FROM project_search_history psh
    WHERE psh.user_id = auth.uid()
      AND psh.has_results = true
    ORDER BY psh.search_count DESC
    LIMIT 10
  ) INTO v_suggestions;

  -- Step 2: empty array if nothing found
  RETURN COALESCE(v_suggestions, ARRAY[]::text[]);

END;
$$;

COMMENT ON FUNCTION public.get_project_search_suggestions IS
'Returns up to 10 search-term suggestions for the Project Search feature.
Accepts user_id uuid — must match auth.uid() or raises 42501.
Step 1: caller own history (has_results=true), ordered by frequency.
Step 2: empty array if no personal history.
SECURITY INVOKER — RLS on project_search_history enforces visibility.
Does NOT expose users.credential_id or any auth identifier.
has_results contract: caller must upsert with has_results=true after a non-empty result set.
Rows with has_results=false are stored but excluded from suggestions.';
