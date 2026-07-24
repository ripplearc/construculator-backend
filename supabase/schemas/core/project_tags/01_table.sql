-- Project Tags Table
-- Many-to-many pivot linking tags to projects, mirroring the session_tags
-- pivot that links tags to calculation sessions.

CREATE TABLE IF NOT EXISTS "public"."project_tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "tag_id" "uuid" NOT NULL,
    "applied_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."project_tags" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."project_tags"
    ADD CONSTRAINT "project_tags_pkey" PRIMARY KEY ("id");


-- Foreign Keys
-- ON DELETE CASCADE: removing a project or a tag removes its pivot rows —
-- a dangling link is meaningless on either side.

ALTER TABLE ONLY "public"."project_tags"
    ADD CONSTRAINT "project_tags_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."project_tags"
    ADD CONSTRAINT "project_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."tags"("id") ON DELETE CASCADE;
