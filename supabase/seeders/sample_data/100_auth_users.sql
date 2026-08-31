-- Auth Users Seeder
-- Creates the GoTrue account backing the seeded public.users row in
-- 103_users.sql. public.users.credential_id points at auth.users.id, but no
-- foreign key enforces it, so without this file the seeded user can be read
-- from the database yet can never sign in. E2E sign-in flows depend on it.
--
-- Runs before 103_users.sql by the seeder loader's alphabetical ordering
-- convention (100_ < 103_) so the credential exists before it is referenced.
-- Nothing in the schema enforces this ordering — see CA-995, which tracks
-- adding the missing public.users.credential_id -> auth.users.id FK.

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
-- Targetless so this also skips a conflict on the users_email_partial_key
-- unique index, not just the primary key — otherwise a developer who already
-- created seeder@example.com by hand (e.g. via the old manual Studio
-- procedure) would abort the whole seed run instead of no-op'ing.
ON CONFLICT DO NOTHING;

-- encrypted_password on auth.users is what resolves the password grant. This
-- identity row is still required for a complete, usable account — GoTrue
-- treats a user with no linked identity as incomplete — but it is not what
-- verifies the password.
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
