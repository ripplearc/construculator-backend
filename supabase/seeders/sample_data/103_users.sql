-- Users Seeder
-- This file creates a single user for seeder reference purposes
-- NOTE: This is for seeder data only - actual users should be created via Supabase API

INSERT INTO "users" (
  "id",
  "credential_id",
  "email",
  "phone",
  "first_name",
  "last_name",
  "professional_role",
  "user_preferences"
) VALUES
  (
    '750e8400-e29b-41d4-a716-446655440000',
    '850e8400-e29b-41d4-a716-446655440000',
    'seeder@example.com',
    '+1-555-0000',
    'Seeder',
    'User',
    (SELECT "id" FROM "professional_roles" WHERE "name" = 'Project Manager'),
    '{"theme": "light", "notifications": true}'
  )
-- Targetless so this also skips a conflict on users_email_key / users_credential_id_key,
-- not just the primary key — matches the fix already applied to 100_auth_users.sql (CA-995).
ON CONFLICT DO NOTHING;
