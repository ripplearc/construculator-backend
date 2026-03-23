-- Shared General Functions

-- Function to automatically update the updated_at timestamp when a row is modified
CREATE OR REPLACE FUNCTION "public"."set_current_timestamp_updated_at"()
    RETURNS TRIGGER
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = "now"();
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."set_current_timestamp_updated_at"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."set_current_timestamp_updated_at"() IS 'Shared trigger function. Sets updated_at to now() on any BEFORE UPDATE trigger. Safe for use across all tables with an updated_at column.';
