-- RLS policies for cost_estimate_logs aligned with cost_estimates permissions

-- Helper predicate to reuse cost_estimates project permission via parent estimate
CREATE OR REPLACE FUNCTION cost_estimate_logs_project_permission(p_estimate_id uuid, p_permission_key text)
RETURNS boolean AS $$
DECLARE
	v_project_id uuid;
BEGIN
	SELECT project_id INTO v_project_id FROM cost_estimates WHERE id = p_estimate_id;
	IF v_project_id IS NULL THEN
		RETURN false;
	END IF;
	RETURN user_has_project_permission(v_project_id, p_permission_key, auth.uid());
END;
$$ LANGUAGE plpgsql STABLE;

-- SELECT: users who can view estimates can view logs
CREATE POLICY cost_estimate_logs_select_policy ON cost_estimate_logs
	FOR SELECT
	USING (cost_estimate_logs_project_permission(estimate_id, 'get_cost_estimations'));
