-- Create calculations table
CREATE TABLE "calculations" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "session_id" uuid NOT NULL REFERENCES "calculation_sessions"("id"),
  "type" calculation_type_enum NOT NULL,
  "calculation_date" timestamptz NOT NULL DEFAULT (now()),
  "computation" jsonb NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now())
);
