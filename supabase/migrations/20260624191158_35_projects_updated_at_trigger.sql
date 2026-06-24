-- CA-752: projects.updated_at was never bumped on UPDATE — there is no
-- trigger maintaining it, unlike cost_estimates. Deploys the shared
-- set_current_timestamp_updated_at() trigger function (already documented
-- in supabase/schemas/_shared/01_functions.sql for reuse across tables,
-- but never actually migrated) and attaches it to projects.
-- https://ripplearc.youtrack.cloud/issue/CA-752

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION "public"."set_current_timestamp_updated_at"()
    RETURNS TRIGGER
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = "now"();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."set_current_timestamp_updated_at"() IS 'Shared trigger function. Sets updated_at to now() on any BEFORE UPDATE trigger. Safe for use across all tables with an updated_at column.';

CREATE OR REPLACE TRIGGER "trigger_update_projects_updated_at"
    BEFORE UPDATE ON "public"."projects"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
