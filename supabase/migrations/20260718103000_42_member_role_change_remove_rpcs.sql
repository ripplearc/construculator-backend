-- CA-807 (3/4): update_member_role + remove_project_member RPCs.
-- Same contract as the invite RPCs: SECURITY DEFINER, permission checks read
-- the DATABASE (never the JWT), level rule and creator immutability enforced
-- server-side.

-- =============================================================================
-- Internal helper: the role level of a joined member holding a permission on a
-- project, or NULL when they are not a joined member / lack the permission.
-- Not exposed to API roles.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.member_permission_level(
  p_project_id uuid,
  p_user_id uuid,
  p_permission_key text
) RETURNS int
LANGUAGE sql
SET search_path = public
STABLE
AS $$
  SELECT r.level
  FROM project_members pm
  JOIN roles r ON r.id = pm.role_id
  WHERE pm.project_id = p_project_id
    AND pm.user_id = p_user_id
    AND pm.membership_status = 'joined'
    AND EXISTS (
      SELECT 1
      FROM role_permissions rp
      JOIN permissions perm ON perm.id = rp.permission_id
      WHERE rp.role_id = pm.role_id
        AND perm.permission_key = p_permission_key
    )
$$;

REVOKE EXECUTE ON FUNCTION public.member_permission_level(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- update_member_role(project_id, member_user_id, new_role_id): change a
-- member's role. The level rule applies to BOTH the member's current role and
-- the new one; the creator's membership is immutable.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_member_role(
  p_project_id uuid,
  p_member_user_id uuid,
  p_new_role_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
  v_caller_level int;
  v_membership_id uuid;
  v_current_level int;
  v_new_level int;
BEGIN
  v_caller_level := member_permission_level(p_project_id, v_caller_id, 'update_member_role');
  IF v_caller_level IS NULL THEN
    RAISE EXCEPTION 'Caller lacks the update_member_role permission on this project'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (SELECT 1 FROM projects WHERE id = p_project_id AND creator_user_id = p_member_user_id) THEN
    RAISE EXCEPTION 'The project creator''s membership cannot be changed'
      USING ERRCODE = '42501';
  END IF;

  SELECT pm.id, r.level INTO v_membership_id, v_current_level
  FROM project_members pm
  JOIN roles r ON r.id = pm.role_id
  WHERE pm.project_id = p_project_id AND pm.user_id = p_member_user_id
  FOR UPDATE OF pm;

  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'No membership found for this user on this project'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT level INTO v_new_level
  FROM roles
  WHERE id = p_new_role_id AND context_type = 'project';

  IF v_new_level IS NULL THEN
    RAISE EXCEPTION 'Unknown project role %', p_new_role_id
      USING ERRCODE = '22023';
  END IF;

  -- Level rule on both sides: the caller can neither touch a member above
  -- their own level nor promote anyone beyond it.
  IF v_current_level > v_caller_level OR v_new_level > v_caller_level THEN
    RAISE EXCEPTION 'Role change exceeds the caller''s own level'
      USING ERRCODE = '42501';
  END IF;

  UPDATE project_members SET role_id = p_new_role_id WHERE id = v_membership_id;
END;
$$;

COMMENT ON FUNCTION public.update_member_role(uuid, uuid, uuid) IS
'Change a project member''s role (CA-807). Requires update_member_role; the level rule applies to both the current and the new role; the creator''s membership is immutable. Checks read the database, not the JWT.';

REVOKE EXECUTE ON FUNCTION public.update_member_role(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_member_role(uuid, uuid, uuid) TO authenticated;

-- =============================================================================
-- remove_project_member(project_id, member_user_id): remove a member, or leave
-- the project yourself. The creator can never be removed (nor leave).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.remove_project_member(
  p_project_id uuid,
  p_member_user_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
BEGIN
  IF EXISTS (SELECT 1 FROM projects WHERE id = p_project_id AND creator_user_id = p_member_user_id) THEN
    RAISE EXCEPTION 'The project creator cannot be removed from the project'
      USING ERRCODE = '42501';
  END IF;

  -- Self-service exception: any member may remove themselves (leave).
  IF v_caller_id <> p_member_user_id
     AND member_permission_level(p_project_id, v_caller_id, 'remove_member') IS NULL THEN
    RAISE EXCEPTION 'Caller lacks the remove_member permission on this project'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM project_members
  WHERE project_id = p_project_id AND user_id = p_member_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No membership found for this user on this project'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_project_member(uuid, uuid) IS
'Remove a member from a project, or leave it yourself (CA-807). Requires remove_member unless removing your own membership; the creator can never be removed. Checks read the database, not the JWT.';

REVOKE EXECUTE ON FUNCTION public.remove_project_member(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_project_member(uuid, uuid) TO authenticated;
