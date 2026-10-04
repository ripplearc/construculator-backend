-- Personal Company Trigger
-- Gives every new users row one company and one Admin company_users row.
-- The Admin role is a project role (context_type = 'project'). It is reused on
-- purpose for company membership, and the trigger finds it by role_name.
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
  SELECT "id" INTO STRICT v_admin_role_id
  FROM "public"."roles"
  WHERE "role_name" = 'Admin';

  INSERT INTO "public"."companies" ("id", "name", "email", "phone")
  VALUES (
    v_company_id,
    COALESCE(NULLIF(trim(NEW."first_name"), ''), 'My') || '''s company',
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

COMMENT ON FUNCTION "public"."create_personal_company_for_new_user"() IS 'Trigger function for users. Creates one personal company and one Admin company_users row for the new user. Not callable by clients.';

CREATE OR REPLACE TRIGGER "trigger_create_personal_company"
    AFTER INSERT ON "public"."users"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."create_personal_company_for_new_user"();


-- A personal company belongs to one user. Deleting a user (or the auth account,
-- which cascades to users) removes the company_users row, and the company goes
-- with it once it has no members, projects or teams.
ALTER TABLE "public"."company_users"
  DROP CONSTRAINT "company_users_user_id_fkey",
  ADD CONSTRAINT "company_users_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION "public"."delete_company_when_last_member_leaves"()
    RETURNS TRIGGER
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  DELETE FROM "public"."companies"
  WHERE "id" = OLD."company_id"
    AND NOT EXISTS (SELECT 1 FROM "public"."company_users" WHERE "company_id" = OLD."company_id")
    AND NOT EXISTS (SELECT 1 FROM "public"."projects" WHERE "owning_company_id" = OLD."company_id")
    AND NOT EXISTS (SELECT 1 FROM "public"."teams" WHERE "company_id" = OLD."company_id");

  RETURN OLD;
END;
$$;

ALTER FUNCTION "public"."delete_company_when_last_member_leaves"() OWNER TO "postgres";

REVOKE EXECUTE ON FUNCTION "public"."delete_company_when_last_member_leaves"() FROM PUBLIC, "anon", "authenticated";

COMMENT ON FUNCTION "public"."delete_company_when_last_member_leaves"() IS 'Trigger function for company_users. Deletes the company when its last company_users row is deleted, unless a project or team still points at it. Not callable by clients.';

CREATE OR REPLACE TRIGGER "trigger_delete_empty_company"
    AFTER DELETE ON "public"."company_users"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."delete_company_when_last_member_leaves"();
