-- Create session_tags table
CREATE TABLE "session_tags" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "session_id" uuid NOT NULL REFERENCES "calculation_sessions"("id"),
  "tag_id" uuid NOT NULL REFERENCES "tags"("id"),
  "applied_at" timestamptz NOT NULL DEFAULT (now())
);
