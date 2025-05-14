-- Create calculation_sessions table
CREATE TABLE "calculation_sessions" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "creator_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "is_private" boolean NOT NULL DEFAULT false,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "last_calculation_at" timestamptz NOT NULL DEFAULT (now())
);
