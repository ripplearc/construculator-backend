-- CA-807 (1/4): project_invitations table — invites addressed to email
-- addresses with no Construculator account yet (project_members.user_id is
-- NOT NULL, so such invites are unrepresentable there). From the CA-784
-- Members design doc, "Schema delta 1".

-- citext gives case-insensitive email storage/comparison.
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE "invitation_status_enum" AS ENUM (
  'pending',
  'accepted',
  'declined',
  'revoked'
);

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

-- Signup conversion looks invitations up by email; the remaining FK columns
-- are indexed per repo convention.
CREATE INDEX ON "project_invitations" ("email");
CREATE INDEX ON "project_invitations" ("role_id");
CREATE INDEX ON "project_invitations" ("invited_by_user_id");
CREATE INDEX ON "project_invitations" ("status");

ALTER TABLE "project_invitations" ENABLE ROW LEVEL SECURITY;

-- SELECT: visible to project members who can invite (they manage the pending
-- list). No INSERT / UPDATE / DELETE policies — all writes go through the
-- SECURITY DEFINER member-management RPCs (CA-807 2/4 onward).
CREATE POLICY "project_invitations_select_policy" ON "project_invitations"
  FOR SELECT
  USING (
    public.jwt_has_project_permission("project_id", 'invite_member')
  );
