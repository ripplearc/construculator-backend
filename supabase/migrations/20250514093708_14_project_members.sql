-- Create project_members table
CREATE TABLE "project_members" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "user_id" uuid NOT NULL REFERENCES "users"("id"),
  "role_id" uuid NOT NULL REFERENCES "roles"("id"),
  "invited_by_user_id" uuid REFERENCES "users"("id"),
  "invited_at" timestamptz NOT NULL DEFAULT (now()),
  "joined_at" timestamptz,
  "membership_status" membership_status_enum NOT NULL DEFAULT 'invited'
);
