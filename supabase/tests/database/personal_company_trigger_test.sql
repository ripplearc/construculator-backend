BEGIN;

-- Tests for CA-710: the AFTER INSERT trigger on users that creates one
-- personal company and one Admin company_users row, and get_my_company_id().

SELECT plan(27);

-- ============================================================
-- Fixtures
-- ============================================================

INSERT INTO professional_roles (id, name)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Company Trigger Test Role');

INSERT INTO auth.users (
  "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
  "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
  "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'dave@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'dave2@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'rollback@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');

-- ============================================================
-- Trigger: one company, one Admin row
-- ============================================================

SELECT has_trigger('public', 'users', 'trigger_create_personal_company', 'users has the personal company trigger');

SELECT lives_ok(
  $$INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
            'dave@example.com', 'Dave', 'Test', 'aaaaaaaa-0000-0000-0000-000000000001', '{}')$$,
  'Inserting a users row succeeds'
);

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1::bigint,
  'The new user has exactly one company_users row'
);

SELECT is(
  (SELECT r.role_name FROM public.company_users cu JOIN public.roles r ON r.id = cu.role_id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'Admin',
  'The company_users row has the Admin role'
);

SELECT is(
  (SELECT c.name FROM public.company_users cu JOIN public.companies c ON c.id = cu.company_id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'Dave''s company',
  'The company name is the first name plus "''s company"'
);

SELECT is(
  (SELECT c.email = 'hidden-' || c.id || '@internal.construculator.app'
          AND c.phone = 'hidden-' || c.id
     FROM public.company_users cu JOIN public.companies c ON c.id = cu.company_id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  true,
  'The company email and phone are hidden values built from the company id'
);

SELECT lives_ok(
  $$INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002',
            'dave2@example.com', 'Dave', 'Other', 'aaaaaaaa-0000-0000-0000-000000000001', '{}')$$,
  'A second user with the same first name can be inserted'
);

SELECT is(
  (SELECT count(DISTINCT cu.company_id) FROM public.company_users cu
     WHERE cu.user_id IN ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002')),
  2::bigint,
  'Two users with the same first name get two separate companies'
);

-- ============================================================
-- Retry: a user who already has a company_users row gets no second company
--
-- The trigger only fires on insert, so a temporary UPDATE trigger runs the
-- same function against a user who already has a company.
-- ============================================================

CREATE TRIGGER zz_retry_probe
  AFTER UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_personal_company_for_new_user();

SELECT lives_ok(
  $$UPDATE public.users SET last_name = 'Retry' WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001'$$,
  'Running the function again for a user with a company succeeds'
);

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1::bigint,
  'The retry did not add a second company_users row'
);

SELECT is(
  (SELECT count(*) FROM public.companies WHERE name = 'Dave''s company'),
  2::bigint,
  'The retry did not add a second company (only the two users'' companies exist)'
);

DELETE FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000002';

SELECT lives_ok(
  $$UPDATE public.users SET last_name = 'Probe' WHERE id = 'bbbbbbbb-0000-0000-0000-000000000002'$$,
  'Running the function for a user without a company succeeds'
);

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000002'),
  1::bigint,
  'The check only skips users who have a company (the probe trigger does create one otherwise)'
);

DROP TRIGGER zz_retry_probe ON public.users;

-- ============================================================
-- Rollback: if the company insert fails, the users insert fails too
-- ============================================================

ALTER TABLE public.companies
  ADD CONSTRAINT zz_reject_rollback_probe CHECK (name <> 'Rollback''s company');

SELECT throws_ok(
  $$INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000003',
            'rollback@example.com', 'Rollback', 'Test', 'aaaaaaaa-0000-0000-0000-000000000001', '{}')$$,
  '23514',
  NULL,
  'The users insert fails when the company insert fails'
);

SELECT is(
  (SELECT count(*) FROM public.users WHERE id = 'bbbbbbbb-0000-0000-0000-000000000003'),
  0::bigint,
  'No users row is left behind'
);

SELECT is(
  (SELECT count(*) FROM public.companies WHERE name = 'Rollback''s company'),
  0::bigint,
  'No company is left behind'
);

ALTER TABLE public.companies DROP CONSTRAINT zz_reject_rollback_probe;

-- ============================================================
-- Privileges
-- ============================================================

SELECT is(
  (SELECT bool_or(has_function_privilege(r, 'public.create_personal_company_for_new_user()', 'EXECUTE'))
     FROM unnest(ARRAY['anon', 'authenticated']) AS r),
  false,
  'Neither anon nor authenticated can execute the trigger function'
);

SELECT is(
  (SELECT p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres'
          AND p.proconfig @> ARRAY['search_path=public']
     FROM pg_proc p WHERE p.oid = 'public.create_personal_company_for_new_user()'::regprocedure),
  true,
  'The trigger function is SECURITY DEFINER, owned by postgres, with search_path set to public'
);

SELECT is(
  (SELECT p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres'
          AND p.proconfig @> ARRAY['search_path=public']
     FROM pg_proc p WHERE p.oid = 'public.get_my_company_id()'::regprocedure),
  true,
  'get_my_company_id() is SECURITY DEFINER, owned by postgres, with search_path set to public'
);

SELECT is(
  has_function_privilege('authenticated', 'public.get_my_company_id()', 'EXECUTE'),
  true,
  'authenticated can execute get_my_company_id()'
);

-- ============================================================
-- get_my_company_id()
-- ============================================================

CREATE TEMP TABLE expected_company AS
  SELECT user_id, company_id FROM public.company_users
  WHERE user_id IN ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002');
GRANT SELECT ON expected_company TO authenticated;

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000001", "role": "authenticated"}', true);

SELECT is(
  public.get_my_company_id(),
  (SELECT company_id FROM expected_company WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'get_my_company_id() returns the caller''s own company, with no internal_user_id claim on the token'
);

SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000002", "role": "authenticated"}', true);

SELECT is(
  public.get_my_company_id(),
  (SELECT company_id FROM expected_company WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000002'),
  'A different caller gets that caller''s own company, not the first one'
);

SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-0000000000ff", "role": "authenticated"}', true);

SELECT is(
  public.get_my_company_id(),
  NULL::uuid,
  'A caller with no users row gets NULL'
);

RESET ROLE;

DELETE FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000002';

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000002", "role": "authenticated"}', true);

SELECT is(
  public.get_my_company_id(),
  NULL::uuid,
  'A caller with a users row but no company gets NULL'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);

SELECT throws_ok(
  $$SELECT public.get_my_company_id()$$,
  '42501',
  NULL,
  'anon cannot call get_my_company_id()'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000001", "role": "authenticated"}', true);

SELECT throws_ok(
  $$SELECT public.create_personal_company_for_new_user()$$,
  '42501',
  NULL,
  'authenticated cannot call the trigger function directly'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM pg_policy WHERE polrelid = 'public.users'::regclass AND polcmd = 'a'),
  0::bigint,
  'No INSERT-only policy was added to users (inserts go through the existing owner policy)'
);

SELECT * FROM finish();
ROLLBACK;
