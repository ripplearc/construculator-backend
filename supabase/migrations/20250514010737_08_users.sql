-- Create users table
CREATE TABLE "users" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "credential_id" uuid UNIQUE NOT NULL,
  "email" varchar(255) UNIQUE NOT NULL,
  "phone" varchar(50) UNIQUE,
  "first_name" varchar(150) NOT NULL,
  "last_name" varchar(150) NOT NULL,
  "professional_role" uuid NOT NULL REFERENCES "professional_roles"("id"),
  "profile_photo_url" text,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  "user_status" user_profile_status_enum NOT NULL DEFAULT 'active',
  "user_preferences" jsonb NOT NULL
);
