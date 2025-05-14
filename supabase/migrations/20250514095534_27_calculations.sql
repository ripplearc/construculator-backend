-- Create calculations table
CREATE TABLE "calculations" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "session_id" uuid NOT NULL REFERENCES "calculation_sessions"("id"),
  "created_by_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "type" calculation_type_enum NOT NULL,
  "computation" jsonb NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "calculations" ("session_id");
CREATE INDEX ON "calculations" ("created_by_user_id");
CREATE INDEX ON "calculations" ("created_at");
CREATE INDEX ON "calculations" ("type");
