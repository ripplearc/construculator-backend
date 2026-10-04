-- Personal Company Trigger
-- Gives every new users row one company and one Admin company_users row.
-- Runs in the same transaction as the users insert, so a failure rolls back both.

CREATE OR REPLACE FUNCTION "public"."create_personal_company_for_new_user"()
    RETURNS TRIGGER
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_company_id uuid := "gen_random_uuid"();
  v_admin_role_id uuid;
BEGIN
  IF EXISTS (
    SELECT 1 FROM "public"."company_users" WHERE "user_id" = NEW."id"
  ) THEN
    RETURN NEW;
  END IF;

  SELECT "id" INTO STRICT v_admin_role_id
  FROM "public"."roles"
  WHERE "role_name" = 'Admin';

  INSERT INTO "public"."companies" ("id", "name", "email", "phone")
  VALUES (
    v_company_id,
    NEW."first_name" || '''s company',
    'hidden-' || v_company_id || '@internal.construculator.app',
    'hidden-' || v_company_id
  );

  INSERT INTO "public"."company_users" ("user_id", "company_id", "role_id")
  VALUES (NEW."id", v_company_id, v_admin_role_id);

  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."create_personal_company_for_new_user"() OWNER TO "postgres";

REVOKE EXECUTE ON FUNCTION "public"."create_personal_company_for_new_user"() FROM PUBLIC, "anon", "authenticated";

COMMENT ON FUNCTION "public"."create_personal_company_for_new_user"() IS 'Trigger function for users. Creates one personal company and one Admin company_users row for the new user. Does nothing if the user already has a company_users row. Not callable by clients.';

CREATE OR REPLACE TRIGGER "trigger_create_personal_company"
    AFTER INSERT ON "public"."users"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."create_personal_company_for_new_user"();
