-- Professional Roles Table
-- Defines available professional roles/occupations for users

CREATE TABLE IF NOT EXISTS "public"."professional_roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying(255) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."professional_roles" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."professional_roles"
    ADD CONSTRAINT "professional_roles_pkey" PRIMARY KEY ("id");


-- Unique Constraints

ALTER TABLE ONLY "public"."professional_roles"
    ADD CONSTRAINT "professional_roles_name_key" UNIQUE ("name");
