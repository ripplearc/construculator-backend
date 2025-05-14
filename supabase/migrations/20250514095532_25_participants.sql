-- Create participants table
CREATE TABLE "participants" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "thread_id" uuid NOT NULL REFERENCES "threads"("id"),
  "participant_id" uuid NOT NULL REFERENCES "users"("id"),
  "created_at" timestamptz NOT NULL DEFAULT (now())
);
