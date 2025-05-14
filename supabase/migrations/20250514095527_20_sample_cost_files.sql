-- Create sample_cost_files table
CREATE TABLE "sample_cost_files" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "file_type" varchar(100) UNIQUE NOT NULL,
  "description" text,
  "download_url" text NOT NULL,
  "version" varchar(50),
  "content_type" varchar(100) NOT NULL,
  "status" general_status_enum NOT NULL DEFAULT 'active',
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "sample_cost_files" ("status");
