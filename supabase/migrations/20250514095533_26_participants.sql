-- Create participants table
CREATE TABLE "participants" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "thread_id" uuid NOT NULL REFERENCES "threads"("id"),
  "participant_id" uuid NOT NULL REFERENCES "users"("id"),
  "created_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "participant_uq" ON "participants" ("thread_id", "participant_id");
CREATE INDEX ON "participants" ("thread_id");
CREATE INDEX ON "participants" ("participant_id");
