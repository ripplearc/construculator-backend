-- RLS Policies for project_members table

-- Policy for SELECT operations on project_members table
-- Users can view project memberships if they are authenticated
CREATE POLICY "project_members_select_policy" ON "project_members"
  FOR SELECT
  USING (auth.uid() IS NOT NULL);