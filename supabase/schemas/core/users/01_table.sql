-- Users Table
-- Core user profiles linked to auth.users via credential_id

CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "credential_id" "uuid" NOT NULL,
    "email" character varying(255) NOT NULL,
    "phone" character varying(50),
    "first_name" character varying(150) NOT NULL,
    "last_name" character varying(150) NOT NULL,
    "professional_role" "uuid" NOT NULL,
    "profile_photo_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_status" "public"."user_profile_status_enum" DEFAULT 'active'::"public"."user_profile_status_enum" NOT NULL,
    "user_preferences" "jsonb" NOT NULL,
    "country_code" "text"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");


-- Unique Constraints

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_credential_id_key" UNIQUE ("credential_id");


ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");


ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");


-- Foreign Keys

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_professional_role_fkey" FOREIGN KEY ("professional_role") REFERENCES "public"."professional_roles"("id");


-- ON DELETE CASCADE: deleting the auth.users account removes the linked
-- profile too — one auth identity owns exactly one users row (see
-- users_credential_id_key above), so there is no scenario where the profile
-- should outlive its own credential. Matches this repo's convention for
-- owned-row FKs (e.g. project_tags, cost_estimate_logs, cost_items all use
-- ON DELETE CASCADE for the same reason).
ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_credential_id_fkey" FOREIGN KEY ("credential_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
