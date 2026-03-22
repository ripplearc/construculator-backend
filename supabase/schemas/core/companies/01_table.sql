-- Companies Table
-- Organizations that own projects and have team members

CREATE TABLE IF NOT EXISTS "public"."companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" character varying(255) NOT NULL,
    "phone" character varying(50) NOT NULL,
    "name" character varying(255) NOT NULL,
    "logo_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."companies" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");


-- Unique Constraints

ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_email_key" UNIQUE ("email");


ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_phone_key" UNIQUE ("phone");
