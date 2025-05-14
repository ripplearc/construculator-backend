-- Create calculation_sessions table
CREATE TABLE "calculation_sessions" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "creator_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "is_private" boolean NOT NULL DEFAULT false,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "last_calculation_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "calculation_sessions" ("project_id");
CREATE INDEX ON "calculation_sessions" ("creator_user_id");
CREATE INDEX ON "calculation_sessions" ("last_calculation_at");
CREATE INDEX ON "calculation_sessions" ("created_at");
