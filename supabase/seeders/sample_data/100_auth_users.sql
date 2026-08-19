-- Auth Users Seeder
-- Creates the GoTrue account backing the seeded public.users row in
-- 103_users.sql. public.users.credential_id points at auth.users.id, but no
-- foreign key enforces it, so without this file the seeded user can be read
-- from the database yet can never sign in. E2E sign-in flows depend on it.
--
-- Runs before 103_users.sql so the credential exists before it is referenced.

-- The seeded password is a fixed, well-known value. It is only ever valid
-- against a local Docker Supabase stack started from this repository, which is
-- never exposed outside the developer machine or the CI runner. Never reuse it
-- for a hosted environment.
INSERT INTO auth.users (
  "instance_id",
  "id",
  "aud",
  "role",
  "email",
  "encrypted_password",
  "email_confirmed_at",
  "raw_app_meta_data",
  "raw_user_meta_data",
  "created_at",
  "updated_at",
  "confirmation_token",
  "recovery_token",
  "email_change_token_new",
  "email_change"
) VALUES
  (
    '00000000-0000-0000-0000-000000000000',
    '850e8400-e29b-41d4-a716-446655440000',
    'authenticated',
    'authenticated',
    'seeder@example.com',
    extensions.crypt('e2e-local-only-password', extensions.gen_salt('bf')),
    now(),
    '{"provider": "email", "providers": ["email"]}',
    '{}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
ON CONFLICT ("id") DO NOTHING;

-- GoTrue resolves the email/password grant through auth.identities, so the
-- account is not usable without a matching email identity.
INSERT INTO auth.identities (
  "provider_id",
  "user_id",
  "identity_data",
  "provider",
  "last_sign_in_at",
  "created_at",
  "updated_at"
) VALUES
  (
    '850e8400-e29b-41d4-a716-446655440000',
    '850e8400-e29b-41d4-a716-446655440000',
    '{"sub": "850e8400-e29b-41d4-a716-446655440000", "email": "seeder@example.com", "email_verified": true, "phone_verified": false}',
    'email',
    now(),
    now(),
    now()
  )
ON CONFLICT ("provider_id", "provider") DO NOTHING;
