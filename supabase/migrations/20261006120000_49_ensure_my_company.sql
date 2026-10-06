-- CA-1262: add ensure_my_company(), which creates the caller's personal company
-- if the caller has none. The app calls it at sign-in.
--
-- Written by hand because config.toml declares schema_paths = [], so the CLI
-- has nothing to diff against.
-- Moves the company creation out of the users trigger into
-- create_personal_company(), so the trigger and ensure_my_company() share it.
-- Mirrors supabase/schemas/core/users/07_personal_company_trigger.sql and the
-- ensure_my_company() function in supabase/schemas/core/users/03_functions.sql.
-- https://ripplearc.youtrack.cloud/issue/CA-1262

CREATE OR REPLACE FUNCTION "public"."create_personal_company"("p_user_id" uuid, "p_first_name" text)
    RETURNS uuid
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
    COALESCE(
      NULLIF(regexp_replace("p_first_name", '^[[:space:]\u200B\u00A0\uFEFF]+|[[:space:]\u200B\u00A0\uFEFF]+$', '', 'g'), '') || '''s company',
      'My company'
    ),
    'hidden-' || v_company_id || '@internal.construculator.app',
    'hidden-' || v_company_id
  );

  INSERT INTO "public"."company_users" ("user_id", "company_id", "role_id")
  VALUES ("p_user_id", v_company_id, v_admin_role_id);

  RETURN v_company_id;
END;
$$;

ALTER FUNCTION "public"."create_personal_company"(uuid, text) OWNER TO "postgres";

REVOKE EXECUTE ON FUNCTION "public"."create_personal_company"(uuid, text) FROM PUBLIC, "anon", "authenticated";

COMMENT ON FUNCTION "public"."create_personal_company"(uuid, text) IS 'Creates one personal company and one Admin company_users row for the given user, and returns the company id. Used by the users trigger and ensure_my_company(). Not callable by clients.';

CREATE OR REPLACE FUNCTION "public"."create_personal_company_for_new_user"()
    RETURNS TRIGGER
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM "public"."create_personal_company"(NEW."id", NEW."first_name");
  RETURN NEW;
END;
$$;

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
