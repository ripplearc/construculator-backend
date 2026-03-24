-- Functions for the global search feature.
-- Includes trigger functions and the two public RPCs.

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
-- global_search RPC
--
-- Parameters: query, filter_by_tag, filter_by_date,
-- filter_by_owner, scope, offset, limit.
--
-- Returns jsonb: { projects: [...], estimations: [...], members: [...] }
--
-- SECURITY INVOKER: existing RLS on projects, cost_estimates and
-- project_members is automatically enforced — no manual permission
-- checks needed inside this function.
--
-- Note: project_status is aliased as "status" in the projects result
-- to match the expected API contract for consumers.
--
-- Note: filter_by_tag is accepted to keep the API contract stable but
-- is currently a no-op. No project-tag join table exists yet; tag
-- filtering will be wired up once that schema is in place.
-- ============================================================
CREATE OR REPLACE FUNCTION public.global_search(
  query text,
  filter_by_tag text DEFAULT NULL,
  filter_by_date timestamptz DEFAULT NULL,
  filter_by_owner uuid DEFAULT NULL,
  scope text DEFAULT NULL,
  "offset" int DEFAULT 0,
  "limit" int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_projects    jsonb := '[]'::jsonb;
  v_estimations jsonb := '[]'::jsonb;
  v_members     jsonb := '[]'::jsonb;
  v_search      text  := '%' || lower(query) || '%';
BEGIN

  -- filter_by_tag is reserved for future use. No project-tag join table
  -- exists yet; the parameter is accepted but not applied to any query.

  -- Projects: visible when scope is dashboard or null (all)
  IF scope IS NULL OR scope = 'dashboard' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(p.*)), '[]'::jsonb)
    INTO v_projects
    FROM (
      SELECT
        id,
        project_name,
        description,
        creator_user_id,
        owning_company_id,
        export_folder_link,
        export_storage_provider,
        created_at,
        updated_at,
        project_status AS status
      FROM projects
      WHERE
        (lower(project_name) LIKE v_search OR lower(COALESCE(description, '')) LIKE v_search)
        AND (filter_by_date IS NULL OR created_at >= filter_by_date)
        AND (filter_by_owner IS NULL OR creator_user_id = filter_by_owner)
      ORDER BY updated_at DESC
      LIMIT "limit" OFFSET "offset"
    ) p;
  END IF;

  -- Cost estimates: visible when scope is dashboard, estimation, or null
  IF scope IS NULL OR scope = 'dashboard' OR scope = 'estimation' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb)
    INTO v_estimations
    FROM (
      SELECT
        id,
        project_id,
        estimate_name,
        estimate_description,
        creator_user_id,
        markup_type,
        overall_markup_value_type,
        overall_markup_value,
        material_markup_value_type,
        material_markup_value,
        labor_markup_value_type,
        labor_markup_value,
        equipment_markup_value_type,
        equipment_markup_value,
        total_cost,
        is_locked,
        locked_by_user_id,
        locked_at,
        created_at,
        updated_at
      FROM cost_estimates
      WHERE
        (lower(estimate_name) LIKE v_search OR lower(COALESCE(estimate_description, '')) LIKE v_search)
        AND (filter_by_date IS NULL OR created_at >= filter_by_date)
        AND (filter_by_owner IS NULL OR creator_user_id = filter_by_owner)
      ORDER BY updated_at DESC
      LIMIT "limit" OFFSET "offset"
    ) e;
  END IF;

  -- Members: visible when scope is dashboard, member, or null
  IF scope IS NULL OR scope = 'dashboard' OR scope = 'member' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(m.*)), '[]'::jsonb)
    INTO v_members
    FROM (
      SELECT DISTINCT ON (u.id)
        u.id,
        u.credential_id,
        u.first_name,
        u.last_name,
        u.professional_role,
        u.profile_photo_url
      FROM project_members pm
      JOIN users u ON pm.user_id = u.id
      WHERE
        pm.membership_status = 'joined'
        AND (
          lower(u.first_name) LIKE v_search
          OR lower(u.last_name) LIKE v_search
          OR lower(u.email) LIKE v_search
        )
      ORDER BY u.id, pm.project_id
      LIMIT "limit" OFFSET "offset"
    ) m;
  END IF;

  RETURN jsonb_build_object(
    'projects',    v_projects,
    'estimations', v_estimations,
    'members',     v_members
  );

END;
$$;

COMMENT ON FUNCTION public.global_search IS
'Global search RPC. Returns projects, cost estimates, and members matching the query.
Respects RLS — users only see records they have permission to access.
project_status is aliased as "status" to match the expected API contract.
filter_by_tag is accepted but currently a no-op (no project-tag schema yet).';

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
