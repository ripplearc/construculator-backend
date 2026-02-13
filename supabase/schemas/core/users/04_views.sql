-- Users Views


-- User Profiles View
-- Public subset of user data for display purposes

CREATE OR REPLACE VIEW "public"."user_profiles" AS
 SELECT "users"."id",
    "users"."credential_id",
    "users"."first_name",
    "users"."last_name",
    "users"."professional_role",
    "users"."profile_photo_url"
   FROM "public"."users";


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";
