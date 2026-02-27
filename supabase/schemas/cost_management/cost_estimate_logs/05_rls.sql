-- Cost Estimate Logs RLS Policies

ALTER TABLE "public"."cost_estimate_logs" ENABLE ROW LEVEL SECURITY;


-- Restrictive Policy - Hide Soft Deleted
-- Prevents access to soft-deleted logs (deleted_at IS NOT NULL)

CREATE POLICY "exclude_soft_deleted_logs" ON "public"."cost_estimate_logs" AS RESTRICTIVE FOR ALL USING (("deleted_at" IS NULL));


-- Select Policy - Enforce project permission

CREATE POLICY "cost_estimate_logs_select_policy" ON "public"."cost_estimate_logs"
	FOR SELECT
	USING (cost_estimate_logs_project_permission(estimate_id, 'get_cost_estimations'));


