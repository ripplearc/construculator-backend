-- Cost Estimates RLS Policies
-- Migrated to JWT-based authorization for improved performance

ALTER TABLE "public"."cost_estimates" ENABLE ROW LEVEL SECURITY;


-- SELECT Policy
-- Users can view cost estimates if they have the 'get_cost_estimations' permission in their JWT

CREATE POLICY "cost_estimates_select_policy" ON "public"."cost_estimates"
  FOR SELECT
  TO authenticated
  USING (
    jwt_has_project_permission(project_id, 'get_cost_estimations')
  );


-- INSERT Policy
-- Users can create cost estimates if they have the 'add_cost_estimation' permission in their JWT

CREATE POLICY "cost_estimates_insert_policy" ON "public"."cost_estimates"
  FOR INSERT
  TO authenticated
  WITH CHECK (
    jwt_has_project_permission(project_id, 'add_cost_estimation')
  );


-- UPDATE Policy
-- Users can update cost estimates if they have the 'edit_cost_estimation' permission in their JWT

CREATE POLICY "cost_estimates_update_policy" ON "public"."cost_estimates"
  FOR UPDATE
  TO authenticated
  USING (
    jwt_has_project_permission(project_id, 'edit_cost_estimation')
  )
  WITH CHECK (
    jwt_has_project_permission(project_id, 'edit_cost_estimation')
  );


-- DELETE Policy
-- Users can delete cost estimates if they have the 'delete_cost_estimation' permission in their JWT

CREATE POLICY "cost_estimates_delete_policy" ON "public"."cost_estimates"
  FOR DELETE
  TO authenticated
  USING (
    jwt_has_project_permission(project_id, 'delete_cost_estimation')
  );


-- Restrictive Policy - Hide Soft Deleted
-- Prevents access to soft-deleted estimates (deleted_at IS NOT NULL)

CREATE POLICY "exclude_soft_deleted_estimates" ON "public"."cost_estimates" AS RESTRICTIVE FOR ALL USING (("deleted_at" IS NULL));
