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
