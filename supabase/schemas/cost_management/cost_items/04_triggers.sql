-- Cost Items Triggers


-- Soft Delete Trigger
-- Intercepts DELETE operations and converts them to soft deletes

CREATE OR REPLACE TRIGGER "trigger_soft_delete_cost_items" BEFORE DELETE ON "public"."cost_items" FOR EACH ROW EXECUTE FUNCTION "public"."handle_soft_delete_cost_items"();
