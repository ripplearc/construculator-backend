-- Cost Items Triggers


-- Soft Delete Trigger
-- Intercepts DELETE operations and converts them to soft deletes

CREATE OR REPLACE TRIGGER "trigger_soft_delete_cost_items" BEFORE DELETE ON "public"."cost_items" FOR EACH ROW EXECUTE FUNCTION "public"."handle_soft_delete_cost_items"();


-- Log Cost Item Addition
CREATE OR REPLACE TRIGGER "trigger_log_cost_item_added"
AFTER INSERT ON "public"."cost_items"
FOR EACH ROW
EXECUTE FUNCTION "public"."log_cost_item_added"();


-- Log Cost Item Updates
CREATE OR REPLACE TRIGGER "trigger_log_cost_item_edited"
AFTER UPDATE ON "public"."cost_items"
FOR EACH ROW
WHEN (
  OLD.item_type IS DISTINCT FROM NEW.item_type OR
  OLD.item_name IS DISTINCT FROM NEW.item_name OR
  OLD.unit_price IS DISTINCT FROM NEW.unit_price OR
  OLD.quantity IS DISTINCT FROM NEW.quantity OR
  OLD.unit_measurement IS DISTINCT FROM NEW.unit_measurement OR
  OLD.calculation IS DISTINCT FROM NEW.calculation OR
  OLD.item_total_cost IS DISTINCT FROM NEW.item_total_cost OR
  OLD.currency IS DISTINCT FROM NEW.currency OR
  OLD.brand IS DISTINCT FROM NEW.brand OR
  OLD.product_link IS DISTINCT FROM NEW.product_link OR
  OLD.description IS DISTINCT FROM NEW.description OR
  OLD.labor_calc_method IS DISTINCT FROM NEW.labor_calc_method OR
  OLD.labor_days IS DISTINCT FROM NEW.labor_days OR
  OLD.labor_hours IS DISTINCT FROM NEW.labor_hours OR
  OLD.labor_unit_type IS DISTINCT FROM NEW.labor_unit_type OR
  OLD.labor_unit_value IS DISTINCT FROM NEW.labor_unit_value OR
  OLD.crew_size IS DISTINCT FROM NEW.crew_size
)
EXECUTE FUNCTION "public"."log_cost_item_edited"();


-- Log Cost Item Removal
CREATE OR REPLACE TRIGGER "trigger_log_cost_item_removed"
AFTER UPDATE ON "public"."cost_items"
FOR EACH ROW
WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
EXECUTE FUNCTION "public"."log_cost_item_removed"();
