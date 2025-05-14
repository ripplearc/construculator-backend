-- Create cost_files table
CREATE TABLE "cost_files" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "version" varchar(20) NOT NULL,
  "filename" varchar(255) NOT NULL,
  "file_url" text NOT NULL,
  "file_size_bytes" bigint,
  "content_type" varchar(100),
  "uploaded_by_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "is_active_file" boolean NOT NULL DEFAULT false,
  "is_sample_file" boolean NOT NULL DEFAULT false,
  "uploaded_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "cost_files" ("project_id");
CREATE INDEX ON "cost_files" ("uploaded_by_user_id");
CREATE INDEX ON "cost_files" ("version");
CREATE INDEX "cost_files_active_idx" ON "cost_files" ("project_id", "is_active_file");
