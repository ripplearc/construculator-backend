-- Cost Estimates Table
-- Stores project cost estimates with markup configurations and lock state

CREATE TABLE IF NOT EXISTS "public"."cost_estimates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "estimate_name" character varying(255) NOT NULL,
    "estimate_description" "text",
    "creator_user_id" "uuid" NOT NULL,
    "markup_type" "public"."markup_type_enum" DEFAULT 'overall'::"public"."markup_type_enum" NOT NULL,
    "overall_markup_value_type" "public"."markup_value_type_enum",
    "overall_markup_value" numeric(18,4),
    "material_markup_value_type" "public"."markup_value_type_enum",
    "material_markup_value" numeric(18,4),
    "labor_markup_value_type" "public"."markup_value_type_enum",
    "labor_markup_value" numeric(18,4),
    "equipment_markup_value_type" "public"."markup_value_type_enum",
    "equipment_markup_value" numeric(18,4),
    "total_cost" numeric(18,2),
    "is_locked" boolean DEFAULT false NOT NULL,
    "locked_by_user_id" "uuid",
    "locked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."cost_estimates" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."cost_estimates"
    ADD CONSTRAINT "cost_estimates_pkey" PRIMARY KEY ("id");


-- Foreign Keys

ALTER TABLE ONLY "public"."cost_estimates"
    ADD CONSTRAINT "cost_estimates_creator_user_id_fkey" FOREIGN KEY ("creator_user_id") REFERENCES "public"."users"("id");


ALTER TABLE ONLY "public"."cost_estimates"
    ADD CONSTRAINT "cost_estimates_locked_by_user_id_fkey" FOREIGN KEY ("locked_by_user_id") REFERENCES "public"."users"("id");


ALTER TABLE ONLY "public"."cost_estimates"
    ADD CONSTRAINT "cost_estimates_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id");
