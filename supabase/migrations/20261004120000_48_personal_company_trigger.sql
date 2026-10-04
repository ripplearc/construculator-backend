-- CA-710: Create one personal company per new user, and add get_my_company_id().
--
-- Written by hand because config.toml declares schema_paths = [], so the CLI
-- has nothing to diff against.
-- Also adds the Admin role (same id as the seeder) so the trigger works on a
-- database that has no seeders.
-- Mirrors supabase/schemas/core/users/07_personal_company_trigger.sql and the
-- get_my_company_id() function in supabase/schemas/core/users/03_functions.sql.
-- https://ripplearc.youtrack.cloud/issue/CA-710

INSERT INTO "public"."roles" ("id", "role_name", "level", "description", "context_type")
VALUES (
  'a50e8400-e29b-41d4-a716-446655440001',
  'Admin',
  4,
  'Full control over project including all cost estimations and team management',
  'project'
)
ON CONFLICT ("role_name") DO NOTHING;


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
