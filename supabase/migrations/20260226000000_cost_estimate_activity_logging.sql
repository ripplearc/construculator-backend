-- Cost Estimate Activity Logging - Triggers and Functions
-- This migration adds automatic logging functionality for cost estimate activities


-- ============================================================================
-- HELPER FUNCTION
-- ============================================================================

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


-- ============================================================================
-- COST ESTIMATES LOGGING FUNCTIONS
-- ============================================================================

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
  v_auth_uid text;
BEGIN
  -- Get credential_id from JWT claims
  BEGIN
    v_auth_uid := current_setting('request.jwt.claims', true)::json->>'sub';
  EXCEPTION WHEN OTHERS THEN
    v_auth_uid := NULL;
  END;

  -- Skip logging if no authenticated user (service role or migration context)
  IF v_auth_uid IS NULL THEN
    RAISE NOTICE 'log_cost_estimate_updated: skipped logging for estimate %, no authenticated user (service role or migration context)', NEW.id;
    RETURN NEW;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_estimate_updated: skipped logging for estimate %, user not found for credential %', NEW.id, v_auth_uid;
    RETURN NEW;
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
  v_auth_uid text;
BEGIN
  -- Get credential_id from JWT claims
  BEGIN
    v_auth_uid := current_setting('request.jwt.claims', true)::json->>'sub';
  EXCEPTION WHEN OTHERS THEN
    v_auth_uid := NULL;
  END;

  -- Skip logging if no authenticated user (service role or migration context)
  IF v_auth_uid IS NULL THEN
    RAISE NOTICE 'log_cost_estimate_deleted: skipped logging for estimate %, no authenticated user (service role or migration context)', NEW.id;
    RETURN NEW;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_estimate_deleted: skipped logging for estimate %, user not found for credential %', NEW.id, v_auth_uid;
    RETURN NEW;
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

-- ============================================================================
-- TRIGGERS - COST ESTIMATES
-- ============================================================================

-- Log Cost Estimate Creation
CREATE OR REPLACE TRIGGER "trigger_log_cost_estimate_created"
AFTER INSERT ON "public"."cost_estimates"
FOR EACH ROW
EXECUTE FUNCTION "public"."log_cost_estimate_created"();


-- Log Cost Estimate Updates (renamed, locked, unlocked)
CREATE OR REPLACE TRIGGER "trigger_log_cost_estimate_updated"
AFTER UPDATE ON "public"."cost_estimates"
FOR EACH ROW
WHEN (
  OLD.estimate_name IS DISTINCT FROM NEW.estimate_name OR
  OLD.is_locked IS DISTINCT FROM NEW.is_locked
)
EXECUTE FUNCTION "public"."log_cost_estimate_updated"();


-- Log Cost Estimate Deletion
CREATE OR REPLACE TRIGGER "trigger_log_cost_estimate_deleted"
AFTER UPDATE ON "public"."cost_estimates"
FOR EACH ROW
WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
EXECUTE FUNCTION "public"."log_cost_estimate_deleted"();


-- ============================================================================
-- COST FILES LOGGING FUNCTIONS
-- ============================================================================

-- Log Cost File Upload
-- Triggered after INSERT on cost_files

CREATE OR REPLACE FUNCTION "public"."log_cost_file_uploaded"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_estimate_id uuid;
  v_auth_uid text;
BEGIN
  -- Get credential_id from JWT claims
  BEGIN
    v_auth_uid := current_setting('request.jwt.claims', true)::json->>'sub';
  EXCEPTION WHEN OTHERS THEN
    v_auth_uid := NULL;
  END;

  -- Skip logging if no authenticated user (service role or migration context)
  IF v_auth_uid IS NULL THEN
    RAISE NOTICE 'log_cost_file_uploaded: skipped logging for file %, no authenticated user (service role or migration context)', NEW.id;
    RETURN NEW;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_file_uploaded: skipped logging for file %, user not found for credential %', NEW.id, v_auth_uid;
    RETURN NEW;
  END IF;

  -- Log to all estimates in this project
  FOR v_estimate_id IN
    SELECT id FROM cost_estimates
    WHERE project_id = NEW.project_id
    AND deleted_at IS NULL
  LOOP
    PERFORM log_cost_estimate_activity(
      v_estimate_id,
      'cost_file_uploaded',
      'Cost file uploaded: ' || NEW.filename,
      v_user_id,
      jsonb_build_object(
        'costFileId', NEW.id::text,
        'fileName', NEW.filename,
        'fileSize', COALESCE(NEW.file_size_bytes, 0),
        'fileType', COALESCE(NEW.content_type, 'unknown')
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_file_uploaded"() OWNER TO "postgres";


-- Log Cost File Deletion
-- Triggered after DELETE on cost_files

CREATE OR REPLACE FUNCTION "public"."log_cost_file_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_estimate_id uuid;
  v_auth_uid text;
BEGIN
  -- Get credential_id from JWT claims
  BEGIN
    v_auth_uid := current_setting('request.jwt.claims', true)::json->>'sub';
  EXCEPTION WHEN OTHERS THEN
    v_auth_uid := NULL;
  END;

  -- Skip logging if no authenticated user (service role or migration context)
  IF v_auth_uid IS NULL THEN
    RAISE NOTICE 'log_cost_file_deleted: skipped logging for file %, no authenticated user (service role or migration context)', OLD.id;
    RETURN OLD;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_file_deleted: skipped logging for file %, user not found for credential %', OLD.id, v_auth_uid;
    RETURN OLD;
  END IF;

  -- Log to all estimates in this project
  FOR v_estimate_id IN
    SELECT id FROM cost_estimates
    WHERE project_id = OLD.project_id
    AND deleted_at IS NULL
  LOOP
    PERFORM log_cost_estimate_activity(
      v_estimate_id,
      'cost_file_deleted',
      'Cost file deleted: ' || OLD.filename,
      v_user_id,
      jsonb_build_object(
        'costFileId', OLD.id::text,
        'fileName', OLD.filename,
        'fileSize', COALESCE(OLD.file_size_bytes, 0),
        'fileType', COALESCE(OLD.content_type, 'unknown')
      )
    );
  END LOOP;

  RETURN OLD;
END;
$$;

ALTER FUNCTION "public"."log_cost_file_deleted"() OWNER TO "postgres";

-- ============================================================================
-- TRIGGERS - COST FILES
-- ============================================================================

-- Log Cost File Upload
CREATE OR REPLACE TRIGGER "trigger_log_cost_file_uploaded"
AFTER INSERT ON "public"."cost_files"
FOR EACH ROW
EXECUTE FUNCTION "public"."log_cost_file_uploaded"();


-- Log Cost File Deletion
CREATE OR REPLACE TRIGGER "trigger_log_cost_file_deleted"
AFTER DELETE ON "public"."cost_files"
FOR EACH ROW
EXECUTE FUNCTION "public"."log_cost_file_deleted"();
