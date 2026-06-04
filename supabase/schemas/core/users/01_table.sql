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
