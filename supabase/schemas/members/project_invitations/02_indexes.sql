-- Project Invitations Indexes

-- Signup conversion looks pending invitations up by email.
CREATE INDEX ON "project_invitations" ("email");

-- FK columns, per repo convention.
CREATE INDEX ON "project_invitations" ("role_id");
CREATE INDEX ON "project_invitations" ("invited_by_user_id");

-- Status filtering (pending list rendering, conversion).
CREATE INDEX ON "project_invitations" ("status");

-- Note: project_id is covered by the leading column of UNIQUE (project_id, email).
