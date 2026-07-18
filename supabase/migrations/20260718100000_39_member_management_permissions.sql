-- CA-806: Member-management permission keys, Viewer role level fix,
-- and tightened RLS on project_members (from the CA-784 Members design doc).

-- =============================================================================
-- 1. New member-management permission keys
-- =============================================================================
INSERT INTO "permissions" ("permission_key", "description", "context_type") VALUES
  ('get_members', 'Permission to view the members of a project', 'project'),
  ('invite_member', 'Permission to invite new members to a project', 'project'),
  ('update_member_role', 'Permission to change the role of a project member', 'project'),
  ('remove_member', 'Permission to remove a member from a project', 'project'),
  ('get_task_assignments', 'Permission to view task assignments within a project', 'project')
ON CONFLICT ("permission_key") DO NOTHING;

-- =============================================================================
-- 2. Map the new permissions to roles per the CA-784 permission matrix
--    get_members:          Viewer, Collaborator, Manager, Admin
--    invite_member:        Collaborator, Manager, Admin
--    update_member_role:   Manager, Admin
--    remove_member:        Manager, Admin
--    get_task_assignments: Collaborator, Manager, Admin
-- =============================================================================
INSERT INTO "role_permissions" ("role_id", "permission_id")
SELECT r."id", p."id"
FROM (VALUES
  ('Viewer',       'get_members'),
  ('Collaborator', 'get_members'),
  ('Manager',      'get_members'),
  ('Admin',        'get_members'),
  ('Collaborator', 'invite_member'),
  ('Manager',      'invite_member'),
  ('Admin',        'invite_member'),
  ('Manager',      'update_member_role'),
  ('Admin',        'update_member_role'),
  ('Manager',      'remove_member'),
  ('Admin',        'remove_member'),
  ('Collaborator', 'get_task_assignments'),
  ('Manager',      'get_task_assignments'),
  ('Admin',        'get_task_assignments')
) AS matrix ("role_name", "permission_key")
JOIN "roles" r ON r."role_name" = matrix."role_name"
JOIN "permissions" p ON p."permission_key" = matrix."permission_key"
ON CONFLICT ("role_id", "permission_id") DO NOTHING;

-- =============================================================================
-- 3. Fix the Viewer role level: the canonical ordering is
--    Admin 4 / Manager 3 / Collaborator 2 / Viewer 1. Viewer was seeded at
--    level 2, tied with Collaborator, which made the two mutually grantable
--    under the "assign roles no higher than your own level" rule.
-- =============================================================================
UPDATE "roles" SET "level" = 1 WHERE "role_name" = 'Viewer' AND "level" = 2;

-- =============================================================================
-- 4. JWT helper: the caller's internal user id (users.id), as injected into
--    app_metadata by the custom access token hook. Returns NULL when absent.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.jwt_internal_user_id()
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  SELECT NULLIF(auth.jwt() -> 'app_metadata' ->> 'internal_user_id', '')::uuid
$$;

COMMENT ON FUNCTION public.jwt_internal_user_id() IS
'Returns the internal users.id of the caller from the JWT app_metadata.internal_user_id claim, or NULL when the claim is absent.';

-- =============================================================================
-- 5. Make user_has_project_permission SECURITY DEFINER.
--    It is called inside RLS policies (projects, cost tables) and needs to read
--    project_members / role_permissions regardless of the caller's own RLS
--    visibility. Until now it relied on the permissive "any authenticated user
--    can read all memberships" policy on project_members, which step 6 removes.
-- =============================================================================
CREATE OR REPLACE FUNCTION "user_has_project_permission"(
  p_project_id uuid,
  p_permission_key text,
  p_user_credential_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  IF p_user_credential_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM "project_members" pm
    JOIN "users" u ON pm.user_id = u.id
    JOIN "role_permissions" rp ON pm.role_id = rp.role_id
    JOIN "permissions" p ON rp.permission_id = p.id
    WHERE pm.project_id = p_project_id
      AND u.credential_id = p_user_credential_id
      AND pm.membership_status = 'joined'
      AND p.permission_key = p_permission_key
  );
END;
$$;

COMMENT ON FUNCTION "user_has_project_permission"(uuid, text, uuid) IS
'Database-side permission check used by RLS policies. SECURITY DEFINER so the check does not depend on the caller''s RLS visibility of project_members.';

-- =============================================================================
-- 6. Tighten project_members SELECT RLS. The previous policy let any
--    authenticated user read every membership row. New policy: a user sees
--    their own rows (including pending "invited" ones, which JWT project
--    claims never cover) plus all rows of projects where they hold the new
--    get_members permission.
-- =============================================================================
DROP POLICY IF EXISTS "project_members_select_policy" ON "project_members";

CREATE POLICY "project_members_select_policy" ON "project_members"
  FOR SELECT
  USING (
    "user_id" = (SELECT public.jwt_internal_user_id())
    OR public.jwt_has_project_permission("project_id", 'get_members')
  );
