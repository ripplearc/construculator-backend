-- Create role_permissions table
CREATE TABLE "role_permissions" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "role_id" uuid NOT NULL REFERENCES "roles"("id"),
  "permission_id" uuid NOT NULL REFERENCES "permissions"("id"),
  "granted_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "role_permission_uq" ON "role_permissions" ("role_id", "permission_id");
CREATE INDEX ON "role_permissions" ("role_id");
CREATE INDEX ON "role_permissions" ("permission_id");
