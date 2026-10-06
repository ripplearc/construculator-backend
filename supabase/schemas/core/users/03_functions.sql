-- Users Functions


-- Email Existence Check
-- Securely checks if an email exists without exposing email data

CREATE OR REPLACE FUNCTION "public"."check_email_exists"("email_input" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM "users"
    WHERE email = email_input
  );
END;
$$;


ALTER FUNCTION "public"."check_email_exists"("email_input" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_email_exists"("email_input" "text") IS 'Securely checks if an email exists in the users table without exposing email data. Bypasses RLS for validation purposes only.';


-- Current Company
-- Returns the company id of the signed-in caller, or NULL if there is none.
-- Needed because company_users has RLS on and no policies.

CREATE OR REPLACE FUNCTION "public"."get_my_company_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT "company_users"."company_id"
  FROM "public"."company_users"
  JOIN "public"."users" ON "users"."id" = "company_users"."user_id"
  WHERE "users"."credential_id" = "auth"."uid"()
  ORDER BY "company_users"."date_associated", "company_users"."id"
  LIMIT 1
$$;


ALTER FUNCTION "public"."get_my_company_id"() OWNER TO "postgres";


REVOKE EXECUTE ON FUNCTION "public"."get_my_company_id"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."get_my_company_id"() TO "authenticated";


COMMENT ON FUNCTION "public"."get_my_company_id"() IS 'Returns the company id of the caller (found through auth.uid() and users.credential_id), or NULL if the caller has no company. Returns only the caller''s own company. Does not need the internal_user_id token claim.';


-- Ensure Company
-- Creates the caller's personal company if there is none, and returns its id.
-- Depends on create_personal_company() in 07_personal_company_trigger.sql.

CREATE OR REPLACE FUNCTION "public"."ensure_my_company"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_first_name text;
  v_company_id uuid;
BEGIN
  -- The row lock makes two calls for the same user wait for each other, so the
  -- second one finds the company the first one created.
  SELECT "id", "first_name" INTO v_user_id, v_first_name
  FROM "public"."users"
  WHERE "credential_id" = "auth"."uid"()
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT "company_id" INTO v_company_id
  FROM "public"."company_users"
  WHERE "user_id" = v_user_id
  ORDER BY "date_associated", "id"
  LIMIT 1;

  IF FOUND THEN
    RETURN v_company_id;
  END IF;

  RETURN "public"."create_personal_company"(v_user_id, v_first_name);
END;
$$;

ALTER FUNCTION "public"."ensure_my_company"() OWNER TO "postgres";

REVOKE EXECUTE ON FUNCTION "public"."ensure_my_company"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."ensure_my_company"() TO "authenticated";

COMMENT ON FUNCTION "public"."ensure_my_company"() IS 'Returns the caller''s company id, creating a personal company with an Admin company_users row first if the caller has none. Safe to call twice: the second call returns the same company. Returns NULL if the caller has no users row yet. The caller is found through auth.uid() and users.credential_id.';
