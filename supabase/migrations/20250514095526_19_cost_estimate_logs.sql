-- Create activity type enum
CREATE TYPE "public"."cost_estimation_activity_type_enum" AS ENUM (
    'cost_estimation_created',
    'cost_estimation_renamed',
    'cost_estimation_exported',
    'cost_estimation_locked',
    'cost_estimation_unlocked',
    'cost_estimation_deleted',
    'cost_item_added',
    'cost_item_edited',
    'cost_item_removed',
    'cost_item_duplicated',
    'task_assigned',
    'task_unassigned',
    'cost_file_uploaded',
    'cost_file_deleted',
    'attachment_added',
    'attachment_removed'
);

ALTER TYPE "public"."cost_estimation_activity_type_enum" OWNER TO "postgres";


-- Create cost_estimate_logs table
CREATE TABLE "cost_estimate_logs" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "activity" "public"."cost_estimation_activity_type_enum" NOT NULL,
  "estimate_id" uuid NOT NULL REFERENCES "cost_estimates"("id"),
  "description" text NOT NULL,
  "user_id" uuid NOT NULL REFERENCES "users"("id"),
  "details" jsonb NOT NULL,
  "logged_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "cost_estimate_logs" ("estimate_id");
CREATE INDEX ON "cost_estimate_logs" ("activity");
CREATE INDEX ON "cost_estimate_logs" ("user_id");
CREATE INDEX ON "cost_estimate_logs" ("logged_at");
