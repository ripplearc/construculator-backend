begin;
select plan(6);

-- The seeded public.users row is unusable for sign-in unless a matching GoTrue
-- credential exists, which is what these assertions guard.

SELECT ok(
  EXISTS (SELECT 1 FROM auth.users WHERE "email" = 'seeder@example.com'),
  'seeded auth user should exist'
);

SELECT is(
  (SELECT "credential_id" FROM public.users WHERE "email" = 'seeder@example.com'),
  (SELECT "id" FROM auth.users WHERE "email" = 'seeder@example.com'),
  'public.users.credential_id should match the seeded auth user id'
);

SELECT ok(
  (SELECT "email_confirmed_at" IS NOT NULL FROM auth.users WHERE "email" = 'seeder@example.com'),
  'seeded auth user should have a confirmed email'
);

SELECT ok(
  (
    SELECT "encrypted_password" = extensions.crypt('e2e-local-only-password', "encrypted_password")
    FROM auth.users WHERE "email" = 'seeder@example.com'
  ),
  'seeded auth user password should verify against the documented seed password'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM auth.identities i
    JOIN auth.users u ON u."id" = i."user_id"
    WHERE u."email" = 'seeder@example.com' AND i."provider" = 'email'
  ),
  'seeded auth user should have an email identity'
);

SELECT is(
  (SELECT i."provider_id" FROM auth.identities i
     JOIN auth.users u ON u."id" = i."user_id"
    WHERE u."email" = 'seeder@example.com' AND i."provider" = 'email'),
  '850e8400-e29b-41d4-a716-446655440000',
  'seeded identity provider_id should match the auth user id'
);

select * from finish();
rollback;
