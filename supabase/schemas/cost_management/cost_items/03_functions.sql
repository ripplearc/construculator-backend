-- Cost Items Functions


-- Soft Delete Handler
-- Converts DELETE operations to soft deletes by setting deleted_at timestamp

CREATE OR REPLACE FUNCTION "public"."handle_soft_delete_cost_items"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF OLD.deleted_at IS NULL THEN
    UPDATE cost_items
    SET deleted_at = now()
    WHERE id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."handle_soft_delete_cost_items"() OWNER TO "postgres";


-- Log Cost Item Addition
-- Triggered after INSERT on cost_items

CREATE OR REPLACE FUNCTION "public"."log_cost_item_added"() RETURNS "trigger"
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
    RAISE NOTICE 'log_cost_item_added: skipped logging for item %, no authenticated user (service role or migration context)', NEW.id;
    RETURN NEW;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_item_added: skipped logging for item %, user not found for credential %', NEW.id, v_auth_uid;
    RETURN NEW;
  END IF;

  PERFORM log_cost_estimate_activity(
    NEW.estimate_id,
    'cost_item_added',
    'Cost item added: ' || NEW.item_name,
    v_user_id,
    jsonb_build_object(
      'costItemId', NEW.id::text,
      'costItemName', NEW.item_name,
      'costItemType', NEW.item_type::text,
      'description', COALESCE(NEW.description, '')
    )
  );
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_item_added"() OWNER TO "postgres";


-- Log Cost Item Edits
-- Triggered after UPDATE on cost_items when fields change

CREATE OR REPLACE FUNCTION "public"."log_cost_item_edited"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_auth_uid text;
  v_edited_fields jsonb;
  v_old_json jsonb;
  v_new_json jsonb;
BEGIN
  -- Get credential_id from JWT claims
  BEGIN
    v_auth_uid := current_setting('request.jwt.claims', true)::json->>'sub';
  EXCEPTION WHEN OTHERS THEN
    v_auth_uid := NULL;
  END;

  -- Skip logging if no authenticated user (service role or migration context)
  IF v_auth_uid IS NULL THEN
    RAISE NOTICE 'log_cost_item_edited: skipped logging for item %, no authenticated user (service role or migration context)', NEW.id;
    RETURN NEW;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_item_edited: skipped logging for item %, user not found for credential %', NEW.id, v_auth_uid;
    RETURN NEW;
  END IF;

  -- Convert rows to jsonb once, excluding metadata fields
  v_old_json := to_jsonb(OLD) - 'id' - 'estimate_id' - 'created_at' - 'updated_at' - 'deleted_at';
  v_new_json := to_jsonb(NEW) - 'id' - 'estimate_id' - 'created_at' - 'updated_at' - 'deleted_at';

  -- Single-pass aggregation: no loop, no concatenations
  SELECT jsonb_object_agg(key, jsonb_build_object('oldValue', v_old_json->key, 'newValue', v_new_json->key))
  INTO v_edited_fields
  FROM jsonb_each(v_old_json)
  WHERE v_old_json->key IS DISTINCT FROM v_new_json->key;

  -- Only log if there are changes
  IF v_edited_fields IS NOT NULL THEN
    PERFORM log_cost_estimate_activity(
      NEW.estimate_id, 'cost_item_edited', 'Cost item edited: ' || NEW.item_name,
      v_user_id, jsonb_build_object('costItemId', NEW.id::text, 'costItemName', NEW.item_name, 'costItemType', NEW.item_type::text, 'editedFields', v_edited_fields)
    );
  END IF;

  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_item_edited"() OWNER TO "postgres";


-- Log Cost Item Removal
-- Triggered after soft delete (UPDATE with deleted_at set)

CREATE OR REPLACE FUNCTION "public"."log_cost_item_removed"() RETURNS "trigger"
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
    RAISE NOTICE 'log_cost_item_removed: skipped logging for item %, no authenticated user (service role or migration context)', NEW.id;
    RETURN NEW;
  END IF;

  -- Look up user_id from credential_id
  SELECT id INTO v_user_id FROM users WHERE credential_id = v_auth_uid::uuid;

  -- Skip if user not found
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'log_cost_item_removed: skipped logging for item %, user not found for credential %', NEW.id, v_auth_uid;
    RETURN NEW;
  END IF;

  PERFORM log_cost_estimate_activity(
    NEW.estimate_id,
    'cost_item_removed',
    'Cost item removed: ' || NEW.item_name,
    v_user_id,
    jsonb_build_object(
      'costItemId', NEW.id::text,
      'costItemName', NEW.item_name,
      'costItemType', NEW.item_type::text
    )
  );
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."log_cost_item_removed"() OWNER TO "postgres";
