-- RLS Policies for projects table
-- These policies ensure users can only access projects they have appropriate permissions for

-- Policy for SELECT operations (viewing projects)
-- Users can view projects if they have the 'view_project' permission for the project
CREATE POLICY "projects_select_policy" ON "projects"
  FOR SELECT
  USING (
    "user_has_project_permission"(
      id,
      'view_project',
      auth.uid()
    )
  );

-- Policy for INSERT operations (creating projects)
-- Any authenticated user can create a project
CREATE POLICY "projects_insert_policy" ON "projects"
  FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
  );

-- Policy for UPDATE operations (editing projects)
-- Users can update projects if they have the 'edit_project' permission
CREATE POLICY "projects_update_policy" ON "projects"
  FOR UPDATE
  USING (
    "user_has_project_permission"(
      id,
      'edit_project',
      auth.uid()
    )
  );

-- Policy for DELETE operations (deleting projects)
-- Users can delete projects if they have the 'delete_project' permission
CREATE POLICY "projects_delete_policy" ON "projects"
  FOR DELETE
  USING (
    "user_has_project_permission"(
      id,
      'delete_project',
      auth.uid()
    )
  );
