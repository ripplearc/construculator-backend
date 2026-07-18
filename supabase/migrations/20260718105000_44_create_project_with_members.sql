-- CA-808: create_project_with_members RPC + creator-membership backfill.
-- Enables CA-163: project creation persists the creator's Admin membership and
-- the invited members in one transaction — a failure in any invite rolls the
-- whole creation back.

-- =============================================================================
-- create_project_with_members(project, invites)
--   p_project: {"project_name": ..., "description"?: ..., "owning_company_id"?: ...}
--   p_invites: [{"email": ..., "role_id": ...}, ...] or [] / NULL for none
-- Returns {"project_id": ..., "outcomes": [...]}.
-- creator_user_id is always the caller — never client-supplied.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_project_with_members(
  p_project jsonb,
  p_invites jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
  v_project_name text := btrim(p_project ->> 'project_name');
  v_admin_role_id uuid;
  v_project_id uuid;
  v_outcomes jsonb := '[]'::jsonb;
BEGIN
  IF v_project_name IS NULL OR v_project_name = '' THEN
    RAISE EXCEPTION 'project_name is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_admin_role_id
  FROM roles
  WHERE role_name = 'Admin' AND context_type = 'project';

  IF v_admin_role_id IS NULL THEN
    RAISE EXCEPTION 'Admin role is not seeded'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO projects (project_name, description, owning_company_id, creator_user_id)
  VALUES (
    v_project_name,
    p_project ->> 'description',
    (p_project ->> 'owning_company_id')::uuid,
    v_caller_id
  )
  RETURNING id INTO v_project_id;

  -- The creator joins immediately as Admin; invited_by is NULL by design.
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
  VALUES (v_project_id, v_caller_id, v_admin_role_id, 'joined', now());

  IF p_invites IS NOT NULL AND jsonb_typeof(p_invites) = 'array' AND jsonb_array_length(p_invites) > 0 THEN
    -- Same engine and invariants as invite_project_members; the creator's
    -- fresh Admin membership satisfies its permission check.
    v_outcomes := process_project_invites(v_project_id, v_caller_id, p_invites);
  END IF;

  RETURN jsonb_build_object('project_id', v_project_id, 'outcomes', v_outcomes);
END;
$$;

COMMENT ON FUNCTION public.create_project_with_members(jsonb, jsonb) IS
'Transactionally create a project, the creator''s Admin membership, and the invited members'' rows/invitations (CA-808, enables CA-163). Any invalid invite aborts the whole creation.';

REVOKE EXECUTE ON FUNCTION public.create_project_with_members(jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_project_with_members(jsonb, jsonb) TO authenticated;

-- =============================================================================
-- Backfill: creator-membership rows for projects that predate the membership
-- model. joined_at/invited_at are set to the project's created_at (the moment
-- the creator factually "joined"). Idempotent: NOT EXISTS + ON CONFLICT.
-- Skipped (with a notice) if the Admin role is not seeded yet.
-- =============================================================================
DO $$
DECLARE
  v_admin_role_id uuid;
  v_backfilled int;
BEGIN
  SELECT id INTO v_admin_role_id
  FROM roles
  WHERE role_name = 'Admin' AND context_type = 'project';

  IF v_admin_role_id IS NULL THEN
    RAISE NOTICE 'creator-membership backfill skipped: Admin role not seeded';
    RETURN;
  END IF;

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, invited_at, joined_at)
  SELECT p.id, p.creator_user_id, v_admin_role_id, 'joined', p.created_at, p.created_at
  FROM projects p
  WHERE NOT EXISTS (
    SELECT 1 FROM project_members pm
    WHERE pm.project_id = p.id AND pm.user_id = p.creator_user_id
  )
  ON CONFLICT (project_id, user_id) DO NOTHING;

  GET DIAGNOSTICS v_backfilled = ROW_COUNT;
  RAISE NOTICE 'creator-membership backfill: % rows inserted', v_backfilled;
END $$;
