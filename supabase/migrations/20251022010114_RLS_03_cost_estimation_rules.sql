-- RLS Policies for cost_estimates table
-- These policies ensure users can only access cost estimates for projects they have appropriate permissions for

-- Optimized permission checking function
CREATE OR REPLACE FUNCTION "user_has_project_permission"(
  p_project_id uuid,
  p_permission_key text,
  p_user_credential_id uuid
) RETURNS boolean AS $$
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
$$ LANGUAGE plpgsql STABLE;

-- Policy for SELECT operations (viewing cost estimates)
-- Users can view cost estimates if they have the 'get_cost_estimations' permission for the project
CREATE POLICY "cost_estimates_select_policy" ON "cost_estimates"
  FOR SELECT
  USING (
    "user_has_project_permission"(
      project_id,
      'get_cost_estimations',
      auth.uid()
    )
  );

-- Policy for INSERT operations (creating cost estimates)
-- Users can create cost estimates if they have the 'add_cost_estimation' permission for the project
CREATE POLICY "cost_estimates_insert_policy" ON "cost_estimates"
  FOR INSERT
  WITH CHECK (
    "user_has_project_permission"(
      project_id,
      'add_cost_estimation',
      auth.uid()
    )
  );

-- Policy for DELETE operations (removing cost estimates)
-- Users can delete cost estimates if they have the 'delete_cost_estimation' permission for the project
CREATE POLICY "cost_estimates_delete_policy" ON "cost_estimates"
  FOR DELETE
  USING (
    "user_has_project_permission"(
      project_id,
      'delete_cost_estimation',
      auth.uid()
    )
  );
