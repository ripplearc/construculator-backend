-- Cost Estimate Logs Functions


-- Helper Function to Log Cost Estimate Activities
-- Creates a new log entry for cost estimate related activities
-- This can be called from triggers or application code

CREATE OR REPLACE FUNCTION "public"."log_cost_estimate_activity"(
  p_estimate_id "uuid",
  p_activity "public"."cost_estimation_activity_type_enum",
  p_description "text",
  p_user_id "uuid",
  p_details "jsonb" DEFAULT '{}'::jsonb
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO cost_estimate_logs (
    estimate_id,
    activity,
    description,
    user_id,
    details
  ) VALUES (
    p_estimate_id,
    p_activity,
    p_description,
    p_user_id,
    p_details
  );
END;
$$;

ALTER FUNCTION "public"."log_cost_estimate_activity"("uuid", "public"."cost_estimation_activity_type_enum", "text", "uuid", "jsonb") OWNER TO "postgres";


-- Soft Delete Handler
-- Converts DELETE operations to soft deletes by setting deleted_at timestamp

CREATE OR REPLACE FUNCTION "public"."handle_soft_delete_cost_estimate_logs"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF OLD.deleted_at IS NULL THEN
    UPDATE cost_estimate_logs
    SET deleted_at = now()
    WHERE id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."handle_soft_delete_cost_estimate_logs"() OWNER TO "postgres";

-- Helper predicate to reuse cost_estimates project permission via parent estimate
CREATE OR REPLACE FUNCTION "public"."cost_estimate_logs_project_permission"(
  p_estimate_id uuid,
  p_permission_key text
) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_project_id uuid;
BEGIN
  SELECT project_id INTO v_project_id FROM cost_estimates WHERE id = p_estimate_id;
  IF v_project_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN user_has_project_permission(v_project_id, p_permission_key, auth.uid());
END;
$$;

ALTER FUNCTION "public"."cost_estimate_logs_project_permission"(uuid, text) OWNER TO "postgres";

