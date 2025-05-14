-- Create tags table
CREATE TABLE "tags" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "name" varchar(100) UNIQUE NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now())
);
