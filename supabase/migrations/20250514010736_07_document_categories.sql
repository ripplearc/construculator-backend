-- Create document_categories table
CREATE TABLE "document_categories" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "category_name" document_category_enum UNIQUE NOT NULL,
  "description" text,
  "status" general_status_enum NOT NULL DEFAULT 'active'
);