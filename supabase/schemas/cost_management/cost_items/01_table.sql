-- Cost Items Table
-- Stores individual line items within cost estimates (materials, labor, equipment)

CREATE TABLE IF NOT EXISTS "public"."cost_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "estimate_id" "uuid" NOT NULL,
    "item_type" "public"."cost_item_type_enum" NOT NULL,
    "item_name" character varying(255) NOT NULL,
    "unit_price" numeric(18,4),
    "quantity" numeric(18,4),
    "unit_measurement" character varying(50),
    "calculation" "jsonb" NOT NULL,
    "item_total_cost" numeric(18,2) NOT NULL,
    "currency" character varying(20) NOT NULL,
    "brand" character varying(100),
    "product_link" "text",
    "description" "text",
    "labor_calc_method" "public"."labor_calc_method_enum",
    "labor_days" numeric(10,2),
    "labor_hours" numeric(10,2),
    "labor_unit_type" character varying(50),
    "labor_unit_value" numeric(18,4),
    "crew_size" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."cost_items" OWNER TO "postgres";


-- Primary Key

ALTER TABLE ONLY "public"."cost_items"
    ADD CONSTRAINT "cost_items_pkey" PRIMARY KEY ("id");


-- Foreign Keys

ALTER TABLE ONLY "public"."cost_items"
    ADD CONSTRAINT "cost_items_estimate_id_fkey" FOREIGN KEY ("estimate_id") REFERENCES "public"."cost_estimates"("id") ON DELETE CASCADE;
