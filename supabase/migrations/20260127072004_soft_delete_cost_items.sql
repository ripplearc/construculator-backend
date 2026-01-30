-- Add deleted_at column for soft delete
ALTER TABLE "cost_items" ADD COLUMN "deleted_at" timestamptz;

CREATE INDEX ON "cost_items" ("deleted_at");

-- Restrictive RLS policy to hide soft-deleted rows
CREATE POLICY "exclude_soft_deleted_items" ON "cost_items"
  AS RESTRICTIVE
  FOR ALL
  USING (deleted_at IS NULL);

-- Function to handle soft delete
CREATE OR REPLACE FUNCTION handle_soft_delete_cost_items()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.deleted_at IS NULL THEN  
    UPDATE cost_items
    SET deleted_at = now()
    WHERE id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger to intercept DELETE and perform soft delete instead
CREATE TRIGGER "trigger_soft_delete_cost_items"
  BEFORE DELETE ON "cost_items"
  FOR EACH ROW
  EXECUTE FUNCTION handle_soft_delete_cost_items();
