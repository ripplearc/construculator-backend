-- Create roles table
CREATE TABLE "roles" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "role_name" varchar(100) UNIQUE NOT NULL,
  "level" int NOT NULL,
  "description" text,
  "context_type" context_type_enum NOT NULL DEFAULT 'project',
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "roles" ("context_type");
