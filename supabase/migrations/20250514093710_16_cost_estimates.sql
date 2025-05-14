-- Create cost_estimates table
CREATE TABLE "cost_estimates" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "estimate_name" varchar(255) NOT NULL,
  "estimate_description" text,
  "creator_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "markup_type" markup_type_enum NOT NULL DEFAULT 'overall',
  "overall_markup_value_type" markup_value_type_enum,
  "overall_markup_value" decimal(18,4),
  "material_markup_value_type" markup_value_type_enum,
  "material_markup_value" decimal(18,4),
  "labor_markup_value_type" markup_value_type_enum,
  "labor_markup_value" decimal(18,4),
  "equipment_markup_value_type" markup_value_type_enum,
  "equipment_markup_value" decimal(18,4),
  "total_cost" decimal(18,2),
  "is_locked" boolean NOT NULL DEFAULT false,
  "locked_by_user_id" uuid REFERENCES "users"("id"),
  "locked_at" timestamptz,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "cost_estimates" ("project_id");
CREATE INDEX ON "cost_estimates" ("creator_user_id");
CREATE INDEX ON "cost_estimates" ("is_locked");
CREATE INDEX ON "cost_estimates" ("updated_at");
CREATE INDEX ON "cost_estimates" ("created_at");
