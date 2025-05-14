-- Create company_users table
CREATE TABLE "company_users" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id" uuid NOT NULL REFERENCES "users"("id"),
  "company_id" uuid NOT NULL REFERENCES "companies"("id"),
  "role_id" uuid NOT NULL REFERENCES "roles"("id"),
  "date_associated" timestamptz NOT NULL DEFAULT (now())
);
