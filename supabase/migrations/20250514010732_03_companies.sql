-- Create companies table
CREATE TABLE "companies" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "email" varchar(255) UNIQUE NOT NULL,
  "phone" varchar(50) UNIQUE NOT NULL,
  "name" varchar(255) NOT NULL,
  "logo_url" text,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);
