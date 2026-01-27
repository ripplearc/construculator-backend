-- Trigger-based cleanup for deletes on cost_estimates
CREATE OR REPLACE FUNCTION handle_delete_cost_estimates()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
	DELETE FROM cost_items WHERE estimate_id = OLD.id;
	DELETE FROM cost_estimate_logs WHERE estimate_id = OLD.id;
	DELETE FROM user_favorites WHERE cost_estimate_id = OLD.id;

	UPDATE attachments
		SET status = 'inactive',
			updated_at = now()
		WHERE cost_estimate_id = OLD.id;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "trigger_handle_delete_cost_estimates"
    AFTER UPDATE ON "cost_estimates"
    FOR EACH ROW
    WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
	EXECUTE FUNCTION handle_delete_cost_estimates();
