-- Add deleted_at column for soft delete
ALTER TABLE "cost_estimates" ADD COLUMN "deleted_at" timestamptz;

CREATE INDEX ON "cost_estimates" ("deleted_at");

-- Restrictive RLS policy to hide soft-deleted rows
CREATE POLICY "exclude_soft_deleted_estimates" ON "cost_estimates"
  AS RESTRICTIVE
  FOR ALL
  USING (deleted_at IS NULL);

-- Function to handle soft delete
CREATE OR REPLACE FUNCTION handle_soft_delete_cost_estimates()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.deleted_at IS NULL THEN
    UPDATE cost_estimates
    SET deleted_at = now()
    WHERE id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger to intercept DELETE and perform soft delete instead
CREATE TRIGGER "trigger_soft_delete_cost_estimates"
  BEFORE DELETE ON "cost_estimates"
  FOR EACH ROW
  EXECUTE FUNCTION handle_soft_delete_cost_estimates();
