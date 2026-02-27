-- Cost Estimates Triggers


-- Update Permission Guard Trigger
-- Enforces column-level permissions on UPDATE operations

CREATE OR REPLACE TRIGGER "trigger_check_cost_estimate_update_permissions" BEFORE UPDATE ON "public"."cost_estimates" FOR EACH ROW EXECUTE FUNCTION "public"."check_cost_estimate_update_permissions"();


-- Cascade Delete Trigger
-- Cleans up related records when estimate is soft deleted

CREATE OR REPLACE TRIGGER "trigger_handle_delete_cost_estimates" AFTER UPDATE ON "public"."cost_estimates" FOR EACH ROW WHEN (((("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL)))) EXECUTE FUNCTION "public"."handle_delete_cost_estimates"();


-- Soft Delete Trigger
-- Intercepts DELETE operations and converts them to soft deletes

CREATE OR REPLACE TRIGGER "trigger_soft_delete_cost_estimates" BEFORE DELETE ON "public"."cost_estimates" FOR EACH ROW EXECUTE FUNCTION "public"."handle_soft_delete_cost_estimates"();
