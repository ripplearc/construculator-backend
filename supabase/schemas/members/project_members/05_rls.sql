-- Project Members RLS Policies

-- SELECT: a user sees their own membership rows (including pending "invited"
-- ones, which JWT project claims never cover) plus all rows of projects where
-- they hold the get_members permission (CA-806).
DROP POLICY IF EXISTS "project_members_select_policy" ON "project_members";

CREATE POLICY "project_members_select_policy" ON "project_members"
  FOR SELECT
  USING (
    "user_id" = (SELECT public.jwt_internal_user_id())
    OR public.jwt_has_project_permission("project_id", 'get_members')
  );

-- No INSERT / UPDATE / DELETE policies: all membership mutations go through
-- the member-management SECURITY DEFINER RPCs (CA-807/CA-808).
