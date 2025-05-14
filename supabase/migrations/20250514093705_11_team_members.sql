-- Create team_members table
CREATE TABLE "team_members" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "team_id" uuid NOT NULL REFERENCES "teams"("id"),
  "member_id" uuid NOT NULL REFERENCES "users"("id"),
  "date_added" timestamptz NOT NULL DEFAULT (now())
);
