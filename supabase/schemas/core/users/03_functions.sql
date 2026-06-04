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
