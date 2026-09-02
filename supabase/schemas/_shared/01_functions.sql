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


-- RLS helper: the caller's internal users.id, from the JWT.
--
-- auth.uid() returns users.credential_id, so a policy on a table keyed by
-- users.id silently matches nothing. custom_access_token_hook already puts the
-- right id on the token, so no users lookup is needed.
CREATE OR REPLACE FUNCTION "public"."jwt_internal_user_id"()
    RETURNS "uuid"
    LANGUAGE "sql"
    SECURITY INVOKER
    STABLE
    -- Pinned like every other function in this repo. auth.jwt() is already
    -- schema-qualified, so 'public' alone is sufficient; the pin exists so a
    -- future edit adding an unqualified reference cannot silently resolve
    -- against a caller-controlled search_path from inside two RLS policies.
    SET "search_path" TO 'public'
    AS $$
  SELECT NULLIF("auth"."jwt"() -> 'app_metadata' ->> 'internal_user_id', '')::"uuid"
$$;

ALTER FUNCTION "public"."jwt_internal_user_id"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."jwt_internal_user_id"() IS 'Shared RLS helper. Returns the caller''s public.users.id from the JWT app_metadata.internal_user_id claim, or NULL when the claim is absent. Use instead of auth.uid() on tables keyed by users.id -- auth.uid() resolves to users.credential_id and never matches. NULL never equals a NOT NULL user_id, so an absent claim denies rather than leaks.';
