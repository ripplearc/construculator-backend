-- Project Invitations RLS Policies

ALTER TABLE "project_invitations" ENABLE ROW LEVEL SECURITY;

-- SELECT: visible to project members who can invite (they manage the pending
-- invite list in the Members tab).
CREATE POLICY "project_invitations_select_policy" ON "project_invitations"
  FOR SELECT
  USING (
    public.jwt_has_project_permission("project_id", 'invite_member')
  );

-- No INSERT / UPDATE / DELETE policies: all writes go through the
-- SECURITY DEFINER member-management RPCs.
