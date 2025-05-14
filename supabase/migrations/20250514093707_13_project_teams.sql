-- Create project_teams table
CREATE TABLE "project_teams" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "team_id" uuid NOT NULL REFERENCES "teams"("id"),
  "role_id" uuid NOT NULL REFERENCES "roles"("id"),
  "assigned_by_user_id" uuid REFERENCES "users"("id"),
  "assigned_at" timestamptz NOT NULL DEFAULT (now())
);
