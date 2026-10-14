-- Cost Items RLS Policies

ALTER TABLE "public"."cost_items" ENABLE ROW LEVEL SECURITY;


-- Permissive policies
-- An item is allowed when the caller holds the permission on the project of its
-- parent estimate, read from the JWT. No cost-item permission key exists, so the
-- estimate keys are reused: get_cost_estimations to read, edit_cost_estimation to
-- insert, update and delete. The subquery runs under the cost_estimates policies.

CREATE POLICY "cost_items_select_policy" ON "public"."cost_items"
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "public"."cost_estimates" e
      WHERE e."id" = "cost_items"."estimate_id"
        AND jwt_has_project_permission(e."project_id", 'get_cost_estimations')
    )
  );

CREATE POLICY "cost_items_insert_policy" ON "public"."cost_items"
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM "public"."cost_estimates" e
      WHERE e."id" = "cost_items"."estimate_id"
        AND jwt_has_project_permission(e."project_id", 'edit_cost_estimation')
    )
  );

CREATE POLICY "cost_items_update_policy" ON "public"."cost_items"
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "public"."cost_estimates" e
      WHERE e."id" = "cost_items"."estimate_id"
        AND jwt_has_project_permission(e."project_id", 'edit_cost_estimation')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM "public"."cost_estimates" e
      WHERE e."id" = "cost_items"."estimate_id"
        AND jwt_has_project_permission(e."project_id", 'edit_cost_estimation')
    )
  );

CREATE POLICY "cost_items_delete_policy" ON "public"."cost_items"
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "public"."cost_estimates" e
      WHERE e."id" = "cost_items"."estimate_id"
        AND jwt_has_project_permission(e."project_id", 'edit_cost_estimation')
    )
  );


-- Restrictive Policy - Hide Soft Deleted
-- Prevents access to soft-deleted items (deleted_at IS NOT NULL)

CREATE POLICY "exclude_soft_deleted_items" ON "public"."cost_items" AS RESTRICTIVE FOR ALL USING (("deleted_at" IS NULL));
