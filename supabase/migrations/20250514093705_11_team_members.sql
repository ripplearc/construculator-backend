-- Create team_members table
CREATE TABLE "team_members" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "team_id" uuid NOT NULL REFERENCES "teams"("id"),
  "member_id" uuid NOT NULL REFERENCES "users"("id"),
  "date_added" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "team_member_uq" ON "team_members" ("team_id", "member_id");
CREATE INDEX ON "team_members" ("member_id");
