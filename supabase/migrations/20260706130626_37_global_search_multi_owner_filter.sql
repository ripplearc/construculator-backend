-- CA-737: Replace global_search's single filter_by_owner with a
-- filter_by_owners uuid[] so the Flutter owner filter sheet can send
-- every selected owner instead of only the alphabetically-first one.
-- NULL and an empty array both mean "no owner filter" — an empty array
-- is the natural "no owners selected" client state and must not
-- silently match zero rows (creator_user_id = ANY('{}') is always false).
-- Generated via `supabase db diff --from=migrations --to=local` from
-- supabase/schemas/global_search/global_search/03_functions.sql per that
-- module's README workflow (old overload dropped in the live DB first,
-- since CREATE OR REPLACE cannot change a signature).
-- https://ripplearc.youtrack.cloud/issue/CA-737

SET check_function_bodies = false;
DROP FUNCTION public.global_search(query text, filter_by_tag text, filter_by_date_from timestamp with time zone, filter_by_date_to timestamp with time zone, filter_by_owner uuid, scope text, projects_offset integer, estimations_offset integer, members_offset integer, "limit" integer);
CREATE FUNCTION public.global_search(query text, filter_by_tag text DEFAULT NULL::text, filter_by_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone, filter_by_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone, filter_by_owners uuid[] DEFAULT NULL::uuid[], scope text DEFAULT NULL::text, projects_offset integer DEFAULT 0, estimations_offset integer DEFAULT 0, members_offset integer DEFAULT 0, "limit" integer DEFAULT 20)
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
        AND (filter_by_owners IS NULL OR cardinality(filter_by_owners) = 0 OR creator_user_id = ANY(filter_by_owners))
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
        AND (filter_by_owners IS NULL OR cardinality(filter_by_owners) = 0 OR creator_user_id = ANY(filter_by_owners))
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
$function$;
GRANT ALL ON FUNCTION public.global_search(text, text, timestamp with time zone, timestamp with time zone, uuid[], text, integer, integer, integer, integer) TO anon;
GRANT ALL ON FUNCTION public.global_search(text, text, timestamp with time zone, timestamp with time zone, uuid[], text, integer, integer, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION public.global_search(text, text, timestamp with time zone, timestamp with time zone, uuid[], text, integer, integer, integer, integer) TO service_role;
