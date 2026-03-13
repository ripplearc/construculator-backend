-- Migrate cost_estimates RLS policies to use JWT claims instead of database lookups
-- This improves performance by reading permissions from JWT tokens rather than querying the database

-- Drop existing RLS policies
DROP POLICY IF EXISTS "cost_estimates_select_policy" ON "cost_estimates";
DROP POLICY IF EXISTS "cost_estimates_insert_policy" ON "cost_estimates";
DROP POLICY IF EXISTS "cost_estimates_update_policy" ON "cost_estimates";
DROP POLICY IF EXISTS "cost_estimates_delete_policy" ON "cost_estimates";

-- Create new JWT-based policies

-- Policy for SELECT operations (viewing cost estimates)
-- Users can view cost estimates if they have the 'get_cost_estimations' permission in their JWT
CREATE POLICY "cost_estimates_select_policy" ON "cost_estimates"
  FOR SELECT
  TO authenticated
  USING (
    jwt_has_project_permission(project_id, 'get_cost_estimations')
  );

-- Policy for INSERT operations (creating cost estimates)
-- Users can create cost estimates if they have the 'add_cost_estimation' permission in their JWT
CREATE POLICY "cost_estimates_insert_policy" ON "cost_estimates"
  FOR INSERT
  TO authenticated
  WITH CHECK (
    jwt_has_project_permission(project_id, 'add_cost_estimation')
  );

-- Policy for UPDATE operations (editing cost estimates)
-- Users can update cost estimates if they have the 'edit_cost_estimation' permission in their JWT
CREATE POLICY "cost_estimates_update_policy" ON "cost_estimates"
  FOR UPDATE
  TO authenticated
  USING (
    jwt_has_project_permission(project_id, 'edit_cost_estimation')
  );

-- Policy for DELETE operations (removing cost estimates)
-- Users can delete cost estimates if they have the 'delete_cost_estimation' permission in their JWT
CREATE POLICY "cost_estimates_delete_policy" ON "cost_estimates"
  FOR DELETE
  TO authenticated
  USING (
    jwt_has_project_permission(project_id, 'delete_cost_estimation')
  );
