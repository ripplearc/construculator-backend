-- Project Invitations Table
-- Invites addressed to email addresses with no Construculator account yet.
-- Registered users are invited directly as project_members rows; this table
-- only carries the "latent" invites that activate at signup (CA-807).

CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE "project_invitations" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "email" citext NOT NULL,
  "role_id" uuid NOT NULL REFERENCES "roles"("id"),
  "invited_by_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "invited_at" timestamptz NOT NULL DEFAULT (now()),
  "status" invitation_status_enum NOT NULL DEFAULT 'pending',
  UNIQUE ("project_id", "email")
);
