-- RLS Policies for cost_estimates table
-- These policies ensure users can only access cost estimates for projects they have appropriate permissions for

-- Policy for SELECT operations (viewing cost estimates)
-- Users can view cost estimates if they have the 'get_cost_estimations' permission for the project
CREATE POLICY "cost_estimates_select_policy" ON "cost_estimates"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM "project_members" pm
      JOIN "users" u ON pm.user_id = u.id
      JOIN "role_permissions" rp ON pm.role_id = rp.role_id
      JOIN "permissions" p ON rp.permission_id = p.id
      WHERE pm.project_id = cost_estimates.project_id
        AND u.credential_id = auth.uid()
        AND pm.membership_status = 'joined'
        AND p.permission_key = 'get_cost_estimations'
    )
  );

-- Policy for INSERT operations (creating cost estimates)
-- Users can create cost estimates if they have the 'add_cost_estimation' permission for the project
CREATE POLICY "cost_estimates_insert_policy" ON "cost_estimates"
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM "project_members" pm
      JOIN "users" u ON pm.user_id = u.id
      JOIN "role_permissions" rp ON pm.role_id = rp.role_id
      JOIN "permissions" p ON rp.permission_id = p.id
      WHERE pm.project_id = cost_estimates.project_id
        AND u.credential_id = auth.uid()
        AND pm.membership_status = 'joined'
        AND p.permission_key = 'add_cost_estimation'
    )
    AND EXISTS (
      SELECT 1
      FROM "users" u
      WHERE u.id = cost_estimates.creator_user_id
        AND u.credential_id = auth.uid()
    )
  );

