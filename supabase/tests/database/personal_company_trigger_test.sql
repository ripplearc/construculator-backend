BEGIN;

-- Tests for CA-710: the AFTER INSERT trigger on users that creates one
-- personal company and one Admin company_users row, and get_my_company_id().

SELECT plan(50);

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
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'client@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'blank@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-0000-0000-000000000006', 'authenticated', 'authenticated',
   'noadmin@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
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
-- Blank first name falls back to "My company"
-- ============================================================

SELECT lives_ok(
  $$INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000005', 'cccccccc-0000-0000-0000-000000000005',
            'blank@example.com', '   ', 'Test', 'aaaaaaaa-0000-0000-0000-000000000001', '{}')$$,
  'A user with a blank first name can be inserted'
);

SELECT is(
  (SELECT c.name FROM public.company_users cu JOIN public.companies c ON c.id = cu.company_id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000005'),
  'My company',
  'A blank first name gives the company name "My company"'
);

-- ============================================================
-- Missing Admin role: the users insert fails
-- ============================================================

UPDATE public.roles SET role_name = 'Admin (test rename)' WHERE role_name = 'Admin';

SELECT throws_ok(
  $$INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000006', 'cccccccc-0000-0000-0000-000000000006',
            'noadmin@example.com', 'Noadmin', 'Test', 'aaaaaaaa-0000-0000-0000-000000000001', '{}')$$,
  'P0002',
  NULL,
  'The users insert fails when there is no role named Admin'
);

UPDATE public.roles SET role_name = 'Admin' WHERE role_name = 'Admin (test rename)';

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
-- Insert as a signed-in client (the app's real path)
-- ============================================================

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000004", "role": "authenticated"}', true);

SELECT lives_ok(
  $$INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000004', 'cccccccc-0000-0000-0000-000000000004',
            'client@example.com', 'Client', 'Test', 'aaaaaaaa-0000-0000-0000-000000000001', '{}')$$,
  'A signed-in client can insert its own users row and the trigger does not fail'
);

SELECT is(
  public.get_my_company_id() IS NOT NULL,
  true,
  'get_my_company_id() returns a company straight after the client insert'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000004'),
  1::bigint,
  'The client insert created exactly one company_users row'
);

SELECT is(
  (SELECT count(*) FROM public.company_users cu JOIN public.roles r ON r.id = cu.role_id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000004' AND r.role_name = 'Admin'),
  1::bigint,
  'That row has the Admin role'
);

SELECT is(
  (SELECT count(*) FROM public.companies c JOIN public.company_users cu ON cu.company_id = c.id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000004' AND c.name = 'Client''s company'),
  1::bigint,
  'Exactly one company was created for the client'
);

-- ============================================================
-- Privileges
-- ============================================================

SELECT is(
  (SELECT bool_or(has_function_privilege(r, 'public.create_personal_company_for_new_user()', 'EXECUTE'))
     FROM unnest(ARRAY['anon', 'authenticated']) AS r),
  false,
  'Neither anon nor authenticated can execute the trigger function'
);

SELECT has_trigger('public', 'company_users', 'trigger_delete_empty_company', 'company_users has the empty company trigger');

SELECT is(
  (SELECT bool_or(has_function_privilege(r, 'public.delete_company_when_last_member_leaves()', 'EXECUTE'))
     FROM unnest(ARRAY['anon', 'authenticated']) AS r),
  false,
  'Neither anon nor authenticated can execute the empty company trigger function'
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
     FROM pg_proc p WHERE p.oid = 'public.delete_company_when_last_member_leaves()'::regprocedure),
  true,
  'The empty company trigger function is SECURITY DEFINER, owned by postgres, with search_path set to public'
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

-- ============================================================
-- Deleting a user
-- ============================================================

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000004", "role": "authenticated"}', true);

SELECT lives_ok(
  $$DELETE FROM public.users WHERE id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  'A signed-in client can delete its own users row after the trigger gave it a company'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000004'),
  0::bigint,
  'Deleting the users row removed its company_users row'
);

SELECT is(
  (SELECT count(*) FROM public.companies WHERE name = 'Client''s company'),
  0::bigint,
  'Deleting the users row removed the company left without members'
);

-- Put user 2 into user 1's company so the company has two members.
INSERT INTO public.company_users (user_id, company_id, role_id)
SELECT 'bbbbbbbb-0000-0000-0000-000000000002', company_id, role_id
FROM public.company_users WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$DELETE FROM auth.users WHERE id = 'cccccccc-0000-0000-0000-000000000001'$$,
  'Deleting an auth account works for a user who has a company'
);

SELECT is(
  (SELECT count(*) FROM public.companies c JOIN expected_company ec ON ec.company_id = c.id
     WHERE ec.user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1::bigint,
  'The company stays while another member is left in it'
);

SELECT lives_ok(
  $$DELETE FROM auth.users WHERE id = 'cccccccc-0000-0000-0000-000000000002'$$,
  'Deleting the last member''s auth account works'
);

SELECT is(
  (SELECT count(*) FROM public.companies c JOIN expected_company ec ON ec.company_id = c.id
     WHERE ec.user_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  0::bigint,
  'The company is removed when its last member is deleted'
);

SELECT is(
  (SELECT count(*) FROM public.users
     WHERE id IN ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002')),
  0::bigint,
  'Deleting the auth accounts removed both users rows'
);

-- ============================================================
-- A company that is still in use is kept when its last member leaves
-- ============================================================

INSERT INTO auth.users (
  "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
  "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
  "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
)
SELECT '00000000-0000-0000-0000-000000000000', ('cccccccc-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'authenticated', 'authenticated', 'inuse' || n || '@example.com',
       extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
       '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''
FROM generate_series(7, 11) AS n;

-- 07: first name made of a tab, a no-break space and a zero-width space around "Tab"
-- 08: owner of a company used by a project, 09: by a team, 10: creator of the project, 11: by a row in another table
INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
SELECT ('bbbbbbbb-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       ('cccccccc-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'inuse' || n || '@example.com',
       CASE WHEN n = 7 THEN E'\t\u00A0\u200BTab\u200B\u00A0\n' ELSE 'Inuse' || n END,
       'Test', 'aaaaaaaa-0000-0000-0000-000000000001', '{}'
FROM generate_series(7, 11) AS n;

SELECT is(
  (SELECT c.name FROM public.company_users cu JOIN public.companies c ON c.id = cu.company_id
     WHERE cu.user_id = 'bbbbbbbb-0000-0000-0000-000000000007'),
  'Tab''s company',
  'Tabs, new lines, no-break spaces and zero-width spaces around the first name are trimmed'
);

CREATE TEMP TABLE in_use_company AS
  SELECT user_id, company_id FROM public.company_users
  WHERE user_id IN ('bbbbbbbb-0000-0000-0000-000000000008', 'bbbbbbbb-0000-0000-0000-000000000009',
                    'bbbbbbbb-0000-0000-0000-000000000011');

INSERT INTO public.projects (project_name, creator_user_id, owning_company_id)
SELECT 'Kept by project', 'bbbbbbbb-0000-0000-0000-000000000010', company_id
FROM in_use_company WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000008';

SELECT lives_ok(
  $$DELETE FROM public.users WHERE id = 'bbbbbbbb-0000-0000-0000-000000000008'$$,
  'A user whose company owns a project can be deleted'
);

SELECT is(
  (SELECT count(*) FROM public.companies c JOIN in_use_company i ON i.company_id = c.id
     WHERE i.user_id = 'bbbbbbbb-0000-0000-0000-000000000008'),
  1::bigint,
  'The company is kept while a project still uses it'
);

INSERT INTO public.teams (company_id, team_name)
SELECT company_id, 'Kept by team' FROM in_use_company WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000009';

SELECT lives_ok(
  $$DELETE FROM public.users WHERE id = 'bbbbbbbb-0000-0000-0000-000000000009'$$,
  'A user whose company has a team can be deleted'
);

SELECT is(
  (SELECT count(*) FROM public.companies c JOIN in_use_company i ON i.company_id = c.id
     WHERE i.user_id = 'bbbbbbbb-0000-0000-0000-000000000009'),
  1::bigint,
  'The company is kept while a team still uses it'
);

-- A table the function has never heard of, standing in for your_rates and any later table.
CREATE TABLE public.zz_company_probe (
  id int PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id)
);

INSERT INTO public.zz_company_probe (id, company_id)
SELECT 1, company_id FROM in_use_company WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000011';

SELECT lives_ok(
  $$DELETE FROM auth.users WHERE id = 'cccccccc-0000-0000-0000-000000000011'$$,
  'Deleting an auth account works when another table points at the company'
);

SELECT is(
  (SELECT count(*) FROM public.users WHERE id = 'bbbbbbbb-0000-0000-0000-000000000011'),
  0::bigint,
  'The users row is gone'
);

SELECT is(
  (SELECT count(*) FROM public.companies c JOIN in_use_company i ON i.company_id = c.id
     WHERE i.user_id = 'bbbbbbbb-0000-0000-0000-000000000011'),
  1::bigint,
  'The company is kept while a row in another table still uses it'
);

SELECT is(
  (SELECT count(*) FROM public.zz_company_probe),
  1::bigint,
  'The row in the other table is untouched'
);

-- ============================================================
-- Policies
-- ============================================================

SELECT is(
  (SELECT array_agg(polname::text ORDER BY polname) || array_agg(polcmd::text ORDER BY polname)
     FROM pg_policy WHERE polrelid = 'public.users'::regclass AND polcmd IN ('a', '*')),
  ARRAY['users_owner_full_access', '*'],
  'The only policy that allows INSERT on users is users_owner_full_access (FOR ALL)'
);

SELECT * FROM finish();
ROLLBACK;
