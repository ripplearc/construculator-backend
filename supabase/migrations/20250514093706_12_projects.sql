-- Create projects table
CREATE TABLE "projects" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_name" varchar(255) NOT NULL,
  "description" text,
  "creator_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "owning_company_id" uuid REFERENCES "companies"("id"),
  "export_folder_link" text,
  "export_storage_provider" storage_provider_enum,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  "project_status" project_status_enum NOT NULL DEFAULT 'active'
);

CREATE INDEX ON "projects" ("creator_user_id");
CREATE INDEX ON "projects" ("owning_company_id");
CREATE INDEX ON "projects" ("created_at");
CREATE INDEX ON "projects" ("updated_at");
CREATE INDEX ON "projects" ("project_status");
