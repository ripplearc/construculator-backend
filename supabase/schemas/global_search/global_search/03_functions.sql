-- Functions for the Global Search feature (dashboard-wide search across
-- projects, cost estimates, and members).

-- ============================================================
-- global_search RPC
--
-- Parameters:
--   query                 text     — required, matched against project_name/
--                                     description, estimate_name/description,
--                                     and member first_name/last_name/email.
--   filter_by_tag         text     — reserved; not yet applied. See CA-596.
--   filter_by_date_from   timestamptz — inclusive lower bound on updated_at.
--   filter_by_date_to     timestamptz — inclusive upper bound on updated_at.
--   filter_by_owner       uuid     — restricts projects/estimates to this
--                                     creator_user_id.
--   scope                 text     — one of 'dashboard', 'estimation',
--                                     'member', or NULL for all.
--   projects_offset, estimations_offset, members_offset, "limit" — pagination.
--
-- Returns: jsonb { projects: [...], estimations: [...], members: [...] }
--
-- Date range filter:
--   Applies to projects.updated_at and cost_estimates.updated_at as an
--   inclusive range. Either bound may be NULL to leave that side
--   unbounded. An inverted range (filter_by_date_from > filter_by_date_to)
--   raises a 22023 error rather than silently returning no rows.
--
-- SECURITY INVOKER: relies on RLS on projects/cost_estimates/project_members/
-- users for row visibility — this function does not bypass RLS.
--
-- Privacy: the members result selects only u.id, first_name, last_name,
-- professional_role, profile_photo_url. Never select users.credential_id
-- here (prior review caught credential_id leakage on this exact RPC).
-- ============================================================
CREATE OR REPLACE FUNCTION public.global_search(
  query text,
  filter_by_tag text DEFAULT NULL::text,
  filter_by_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone,
  filter_by_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone,
  filter_by_owner uuid DEFAULT NULL::uuid,
  scope text DEFAULT NULL::text,
  projects_offset integer DEFAULT 0,
  estimations_offset integer DEFAULT 0,
  members_offset integer DEFAULT 0,
  "limit" integer DEFAULT 20
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_projects    jsonb := '[]'::jsonb;
  v_estimations jsonb := '[]'::jsonb;
  v_members     jsonb := '[]'::jsonb;
  v_search      text  := '%' || lower(query) || '%';
BEGIN

  -- Validate scope — unknown values would silently return empty results.
  IF scope IS NOT NULL AND scope NOT IN ('dashboard', 'estimation', 'member') THEN
    RAISE EXCEPTION 'Invalid scope: %', scope USING ERRCODE = '22023';
  END IF;

  -- Reject an inverted range outright rather than silently returning no
  -- rows, so the Flutter client can surface a validation message.
  IF filter_by_date_from IS NOT NULL AND filter_by_date_to IS NOT NULL
     AND filter_by_date_from > filter_by_date_to THEN
    RAISE EXCEPTION 'filter_by_date_from must not be after filter_by_date_to'
      USING ERRCODE = '22023';
  END IF;

  -- TODO: [CA-596] Wire up filter_by_tag once project-tag schema exists.
  -- https://ripplearc.youtrack.cloud/issue/CA-596
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
        AND (filter_by_date_from IS NULL OR updated_at >= filter_by_date_from)
        AND (filter_by_date_to IS NULL OR updated_at <= filter_by_date_to)
        AND (filter_by_owner IS NULL OR creator_user_id = filter_by_owner)
      ORDER BY updated_at DESC
      LIMIT "limit" OFFSET projects_offset
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
        AND (filter_by_date_from IS NULL OR updated_at >= filter_by_date_from)
        AND (filter_by_date_to IS NULL OR updated_at <= filter_by_date_to)
        AND (filter_by_owner IS NULL OR creator_user_id = filter_by_owner)
      ORDER BY updated_at DESC
      LIMIT "limit" OFFSET estimations_offset
    ) e;
  END IF;

  -- Members: visible when scope is dashboard, member, or null
  IF scope IS NULL OR scope = 'dashboard' OR scope = 'member' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(m.*)), '[]'::jsonb)
    INTO v_members
    FROM (
      SELECT DISTINCT ON (u.id)
        u.id,
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
      LIMIT "limit" OFFSET members_offset
    ) m;
  END IF;

  RETURN jsonb_build_object(
    'projects',    v_projects,
    'estimations', v_estimations,
    'members',     v_members
  );

END;
$function$
;
