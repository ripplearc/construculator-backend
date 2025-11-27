-- RLS Policies for roles and permissions tables

-- Policy for SELECT operations on permissions table
-- Users can view permissions if they are authenticated
-- This allows users to see what permissions are available in the system
CREATE POLICY "permissions_select_policy" ON "permissions"
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Policy for SELECT operations on role_permissions table
-- Users can view role permissions if they are authenticated
-- This allows users to see what permissions are assigned to different roles
CREATE POLICY "role_permissions_select_policy" ON "role_permissions"
  FOR SELECT
  USING (auth.uid() IS NOT NULL);
