begin;
select plan(5);

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

select * from finish();
rollback;
