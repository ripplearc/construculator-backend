-- Cost Files Table
-- Stores uploaded cost estimate template files for projects

CREATE TABLE IF NOT EXISTS "public"."cost_files" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "version" character varying(20) NOT NULL,
    "filename" character varying(255) NOT NULL,
    "file_url" "text" NOT NULL,
    "file_size_bytes" bigint,
    "content_type" character varying(100),
    "uploaded_by_user_id" "uuid" NOT NULL,
    "is_active_file" boolean DEFAULT false NOT NULL,
    "is_sample_file" boolean DEFAULT false NOT NULL,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cost_files" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."cost_files"
    ADD CONSTRAINT "cost_files_pkey" PRIMARY KEY ("id");


-- Foreign Keys

ALTER TABLE ONLY "public"."cost_files"
    ADD CONSTRAINT "cost_files_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id");


ALTER TABLE ONLY "public"."cost_files"
    ADD CONSTRAINT "cost_files_uploaded_by_user_id_fkey" FOREIGN KEY ("uploaded_by_user_id") REFERENCES "public"."users"("id");
