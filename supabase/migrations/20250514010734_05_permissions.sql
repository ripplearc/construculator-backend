-- Create permissions table
CREATE TABLE "permissions" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "permission_key" varchar(100) UNIQUE NOT NULL,
  "description" text,
  "context_type" context_type_enum NOT NULL DEFAULT 'project',
  "created_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "permissions" ("context_type");
