-- Cost Estimate Logs Table
-- Stores activity/audit logs for cost estimates

CREATE TABLE IF NOT EXISTS "public"."cost_estimate_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "estimate_id" "uuid" NOT NULL,
    "activity" "public"."cost_estimation_activity_type_enum" NOT NULL,
    "description" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "details" "jsonb" NOT NULL,
    "logged_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."cost_estimate_logs" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."cost_estimate_logs"
    ADD CONSTRAINT "cost_estimate_logs_pkey" PRIMARY KEY ("id");


-- Foreign Keys

ALTER TABLE ONLY "public"."cost_estimate_logs"
    ADD CONSTRAINT "cost_estimate_logs_estimate_id_fkey" FOREIGN KEY ("estimate_id") REFERENCES "public"."cost_estimates"("id") ON DELETE CASCADE;


ALTER TABLE ONLY "public"."cost_estimate_logs"
    ADD CONSTRAINT "cost_estimate_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");
