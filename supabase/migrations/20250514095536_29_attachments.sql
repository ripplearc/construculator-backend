-- Create attachments table
CREATE TABLE "attachments" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "cost_estimate_id" uuid REFERENCES "cost_estimates"("id"),
  "calculation_id" uuid REFERENCES "calculations"("id"),
  "project_id" uuid NOT NULL REFERENCES "projects"("id"),
  "uploaded_by_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "document_category_id" uuid REFERENCES "document_categories"("id"),
  "attachment_parent_type" attachment_parent_type_enum NOT NULL,
  "attachment_type" attachment_type_enum NOT NULL,
  "file_url" text NOT NULL,
  "status" general_status_enum NOT NULL DEFAULT 'active',
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);
