-- Cost Estimates Functions


-- Update Permission Guard
-- Enforces column-level permissions and immutability rules for updates

CREATE OR REPLACE FUNCTION "public"."check_cost_estimate_update_permissions"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
  delete_changed boolean;
  lock_changed boolean;
  immutable_changed boolean;
BEGIN
  IF current_user IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;

  delete_changed := (OLD.deleted_at IS DISTINCT FROM NEW.deleted_at)
    OR (NEW.deleted_at IS NOT NULL);
  lock_changed := (OLD.is_locked IS DISTINCT FROM NEW.is_locked);

  immutable_changed := ROW(
    OLD.id,
    OLD.project_id,
    OLD.creator_user_id,
    OLD.locked_by_user_id,
    OLD.locked_at,
    OLD.markup_type,
    OLD.overall_markup_value_type,
    OLD.overall_markup_value,
    OLD.material_markup_value_type,
    OLD.material_markup_value,
    OLD.labor_markup_value_type,
    OLD.labor_markup_value,
    OLD.equipment_markup_value_type,
    OLD.equipment_markup_value,
    OLD.total_cost,
    OLD.created_at
  ) IS DISTINCT FROM ROW(
    NEW.id,
    NEW.project_id,
    NEW.creator_user_id,
    NEW.locked_by_user_id,
    NEW.locked_at,
    NEW.markup_type,
    NEW.overall_markup_value_type,
    NEW.overall_markup_value,
    NEW.material_markup_value_type,
    NEW.material_markup_value,
    NEW.labor_markup_value_type,
    NEW.labor_markup_value,
    NEW.equipment_markup_value_type,
    NEW.equipment_markup_value,
    NEW.total_cost,
    NEW.created_at
  );

  IF immutable_changed THEN
    RAISE EXCEPTION 'Immutable columns on cost_estimates cannot be updated'
      USING ERRCODE = '42501';
  END IF;

  IF delete_changed THEN
    IF NOT "user_has_project_permission"(
      NEW.project_id,
      'delete_cost_estimation',
      auth.uid()
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions: delete_cost_estimation required to mark as deleted'
      USING ERRCODE = '42501';
    END IF;
  END IF;

  IF lock_changed THEN
    IF NOT "user_has_project_permission"(
      NEW.project_id,
      'lock_cost_estimation',
      auth.uid()
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions: lock_cost_estimation required to modify lock columns'
        USING ERRCODE = '42501';
    END IF;


    IF NEW.is_locked THEN
      NEW.locked_by_user_id := (SELECT id FROM users WHERE credential_id = auth.uid());
      NEW.locked_at := now();
    ELSE
      NEW.locked_by_user_id := NULL;
      NEW.locked_at := NULL;
    END IF;
  END IF;

  NEW.updated_at = now();

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_cost_estimate_update_permissions"() OWNER TO "postgres";


-- Cascade Delete Handler
-- Handles cleanup of related records when estimate is soft deleted

CREATE OR REPLACE FUNCTION "public"."handle_delete_cost_estimates"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
$$;


ALTER FUNCTION "public"."handle_delete_cost_estimates"() OWNER TO "postgres";


-- Soft Delete Handler
-- Converts DELETE operations to soft deletes by setting deleted_at timestamp

CREATE OR REPLACE FUNCTION "public"."handle_soft_delete_cost_estimates"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF OLD.deleted_at IS NULL THEN
    UPDATE cost_estimates
    SET deleted_at = now()
    WHERE id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."handle_soft_delete_cost_estimates"() OWNER TO "postgres";


-- Log Cost Estimate Creation
-- Triggered after INSERT on cost_estimates

CREATE OR REPLACE FUNCTION "public"."log_cost_estimate_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM log_cost_estimate_activity(
    NEW.id,
    'cost_estimation_created',
    'Cost estimate created: ' || NEW.estimate_name,
    NEW.creator_user_id,
    jsonb_build_object(
      'name', NEW.estimate_name,
      'description', COALESCE(NEW.estimate_description, '')
    )
  );
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_estimate_created"() OWNER TO "postgres";


-- Log Cost Estimate Updates (Renamed, Locked, Unlocked)
-- Triggered after UPDATE on cost_estimates when name or lock status changes

CREATE OR REPLACE FUNCTION "public"."log_cost_estimate_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id FROM users WHERE credential_id = auth.uid();

  -- If no user found from auth, fall back to creator
  IF v_user_id IS NULL THEN
    v_user_id := NEW.creator_user_id;
  END IF;

  -- Log name change (Renamed)
  IF OLD.estimate_name IS DISTINCT FROM NEW.estimate_name THEN
    PERFORM log_cost_estimate_activity(
      NEW.id,
      'cost_estimation_renamed',
      'Cost estimate renamed from "' || OLD.estimate_name || '" to "' || NEW.estimate_name || '"',
      v_user_id,
      jsonb_build_object(
        'oldName', OLD.estimate_name,
        'newName', NEW.estimate_name
      )
    );
  END IF;

  -- Log lock status change
  IF OLD.is_locked IS DISTINCT FROM NEW.is_locked THEN
    IF NEW.is_locked THEN
      PERFORM log_cost_estimate_activity(
        NEW.id,
        'cost_estimation_locked',
        'Cost estimate locked',
        COALESCE(NEW.locked_by_user_id, v_user_id),
        '{}'::jsonb
      );
    ELSE
      PERFORM log_cost_estimate_activity(
        NEW.id,
        'cost_estimation_unlocked',
        'Cost estimate unlocked',
        v_user_id,
        '{}'::jsonb
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_estimate_updated"() OWNER TO "postgres";


-- Log Cost Estimate Deletion
-- Triggered after soft delete (UPDATE with deleted_at set)

CREATE OR REPLACE FUNCTION "public"."log_cost_estimate_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id FROM users WHERE credential_id = auth.uid();

  IF v_user_id IS NULL THEN
    v_user_id := NEW.creator_user_id;
  END IF;

  PERFORM log_cost_estimate_activity(
    NEW.id,
    'cost_estimation_deleted',
    'Cost estimate deleted: ' || NEW.estimate_name,
    v_user_id,
    '{}'::jsonb
  );
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_estimate_deleted"() OWNER TO "postgres";
