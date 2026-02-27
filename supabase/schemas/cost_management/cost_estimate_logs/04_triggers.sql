-- Cost Estimate Logs Triggers


-- Soft Delete Trigger
-- Intercepts DELETE operations and converts them to soft deletes

CREATE OR REPLACE TRIGGER "trigger_soft_delete_cost_estimate_logs" BEFORE DELETE ON "public"."cost_estimate_logs" FOR EACH ROW EXECUTE FUNCTION "public"."handle_soft_delete_cost_estimate_logs"();
