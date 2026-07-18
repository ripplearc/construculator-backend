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


-- JWT helper: the caller's internal user id (users.id), as injected into
-- app_metadata by the custom access token hook. Returns NULL when absent.
CREATE OR REPLACE FUNCTION "public"."jwt_internal_user_id"()
RETURNS uuid
LANGUAGE "sql"
SECURITY INVOKER
STABLE
AS $$
  SELECT NULLIF(auth.jwt() -> 'app_metadata' ->> 'internal_user_id', '')::uuid
$$;

COMMENT ON FUNCTION "public"."jwt_internal_user_id"() IS 'Returns the internal users.id of the caller from the JWT app_metadata.internal_user_id claim, or NULL when the claim is absent.';


-- Database-side permission check used by RLS policies (projects, cost tables).
-- SECURITY DEFINER (since CA-806) so the check does not depend on the caller's
-- own RLS visibility of project_members.
CREATE OR REPLACE FUNCTION "public"."user_has_project_permission"(
  p_project_id uuid,
  p_permission_key text,
  p_user_credential_id uuid
) RETURNS boolean
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
STABLE
AS $$
BEGIN
  IF p_user_credential_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM "project_members" pm
    JOIN "users" u ON pm.user_id = u.id
    JOIN "role_permissions" rp ON pm.role_id = rp.role_id
    JOIN "permissions" p ON rp.permission_id = p.id
    WHERE pm.project_id = p_project_id
      AND u.credential_id = p_user_credential_id
      AND pm.membership_status = 'joined'
      AND p.permission_key = p_permission_key
  );
END;
$$;

COMMENT ON FUNCTION "public"."user_has_project_permission"(uuid, text, uuid) IS 'Database-side permission check used by RLS policies. SECURITY DEFINER so the check does not depend on the caller''s RLS visibility of project_members.';
