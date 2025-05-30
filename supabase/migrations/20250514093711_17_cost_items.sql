-- Create cost_items table
CREATE TABLE "cost_items" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "estimate_id" uuid NOT NULL REFERENCES "cost_estimates"("id"),
  "item_type" cost_item_type_enum NOT NULL,
  "item_name" varchar(255) NOT NULL,
  "unit_price" decimal(18,4),
  "quantity" decimal(18,4),
  "unit_measurement" varchar(50),
  "calculation" jsonb NOT NULL,
  "item_total_cost" decimal(18,2) NOT NULL,
  "currency" varchar(20) NOT NULL,
  "brand" varchar(100),
  "product_link" text,
  "description" text,
  "labor_calc_method" labor_calc_method_enum,
  "labor_days" decimal(10,2),
  "labor_hours" decimal(10,2),
  "labor_unit_type" varchar(50),
  "labor_unit_value" decimal(18,4),
  "crew_size" int,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "cost_items" ("estimate_id");
CREATE INDEX ON "cost_items" ("item_type");
CREATE INDEX ON "cost_items" ("created_at");
CREATE INDEX ON "cost_items" ("updated_at");
