-- CA-1182: let signed-in users read and write cost items.
--
-- cost_items had RLS on and only a RESTRICTIVE policy (exclude_soft_deleted_items).
-- A restrictive policy removes rows and never grants access, so with no
-- permissive policy every select, insert, update and delete by `authenticated`
-- was denied. RLS does not follow the foreign key to cost_estimates.
--
-- Each policy allows an item when the caller holds the matching permission on
-- the project of the item's parent estimate, read from the JWT like the
-- cost_estimates policies. No cost-item permission key exists, so the
-- estimate keys are reused: get_cost_estimations to read, edit_cost_estimation
-- to insert, update and delete.
--
-- Every write also needs get_cost_estimations, because the lookup of the parent
-- estimate runs under its select policy.
--
-- The EXISTS subquery runs under the cost_estimates policies, so an item of a
-- soft-deleted estimate or of a project the caller cannot read stays hidden.
--
-- Mirrors supabase/schemas/cost_management/cost_items/05_rls.sql.
--
-- Rollback (manual; Supabase migrations are append-only):
--   DROP POLICY "cost_items_select_policy" ON public.cost_items;
--   DROP POLICY "cost_items_insert_policy" ON public.cost_items;
--   DROP POLICY "cost_items_update_policy" ON public.cost_items;
--   DROP POLICY "cost_items_delete_policy" ON public.cost_items;
--
-- https://ripplearc.youtrack.cloud/issue/CA-1182

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
