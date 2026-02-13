-- Cost Estimates RLS Policies

ALTER TABLE "public"."cost_estimates" ENABLE ROW LEVEL SECURITY;


-- DELETE Policy
-- Users can delete estimates if they have delete_cost_estimation permission

CREATE POLICY "cost_estimates_delete_policy" ON "public"."cost_estimates" FOR DELETE USING ("public"."user_has_project_permission"("project_id", 'delete_cost_estimation'::"text", "auth"."uid"()));


-- INSERT Policy
-- Users can create estimates if they have add_cost_estimation permission

CREATE POLICY "cost_estimates_insert_policy" ON "public"."cost_estimates" FOR INSERT WITH CHECK ("public"."user_has_project_permission"("project_id", 'add_cost_estimation'::"text", "auth"."uid"()));


-- SELECT Policy
-- Users can view estimates if they have get_cost_estimations permission

CREATE POLICY "cost_estimates_select_policy" ON "public"."cost_estimates" FOR SELECT USING ("public"."user_has_project_permission"("project_id", 'get_cost_estimations'::"text", "auth"."uid"()));


-- UPDATE Policy
-- Users can edit estimates if they have edit_cost_estimation permission

CREATE POLICY "cost_estimates_update_policy" ON "public"."cost_estimates" FOR UPDATE USING ("public"."user_has_project_permission"("project_id", 'edit_cost_estimation'::"text", "auth"."uid"()));


-- Restrictive Policy - Hide Soft Deleted
-- Prevents access to soft-deleted estimates (deleted_at IS NOT NULL)

CREATE POLICY "exclude_soft_deleted_estimates" ON "public"."cost_estimates" AS RESTRICTIVE FOR ALL USING (("deleted_at" IS NULL));
