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
