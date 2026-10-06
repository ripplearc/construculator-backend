BEGIN;

-- Tests for CA-1262: ensure_my_company() creates the caller's personal company
-- when there is none, and is safe to call twice.

SELECT plan(14);

INSERT INTO professional_roles (id, name)
VALUES ('aaaaaaaa-0000-0000-0000-000000000002', 'Ensure Company Test Role');

INSERT INTO auth.users (
  "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
  "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
  "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'erin@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'frank@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'gina@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
   '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');

INSERT INTO public.users (id, credential_id, email, first_name, last_name, professional_role, user_preferences)
VALUES
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
   'erin@example.com', 'Erin', 'Test', 'aaaaaaaa-0000-0000-0000-000000000002', '{}'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000002',
   'frank@example.com', 'Frank', 'Test', 'aaaaaaaa-0000-0000-0000-000000000002', '{}'),
  ('eeeeeeee-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000003',
   'gina@example.com', '  ', 'Test', 'aaaaaaaa-0000-0000-0000-000000000002', '{}');

CREATE TEMP TABLE erin_company AS
  SELECT company_id FROM public.company_users WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000001';
GRANT SELECT ON erin_company TO authenticated;

-- Erin and Gina lose the company the signup trigger gave them, like an account
-- that signed up before the trigger shipped. Frank keeps his.
DELETE FROM public.company_users
WHERE user_id IN ('eeeeeeee-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000003');
DELETE FROM public.companies WHERE id = (SELECT company_id FROM erin_company);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-000000000001", "role": "authenticated"}', true);

CREATE TEMP TABLE first_call AS SELECT public.ensure_my_company() AS company_id;

SELECT isnt(
  (SELECT company_id FROM first_call),
  NULL::uuid,
  'A caller with no company gets a company id back'
);

SELECT is(
  public.get_my_company_id(),
  (SELECT company_id FROM first_call),
  'get_my_company_id() returns the company that ensure_my_company() created'
);

SELECT is(
  public.ensure_my_company(),
  (SELECT company_id FROM first_call),
  'Calling it a second time returns the same company'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  1::bigint,
  'Calling it twice leaves one company_users row'
);

SELECT is(
  (SELECT count(*) FROM public.companies WHERE name = 'Erin''s company'),
  1::bigint,
  'Calling it twice leaves one company named after the first name'
);

SELECT is(
  (SELECT r.role_name FROM public.company_users cu JOIN public.roles r ON r.id = cu.role_id
    WHERE cu.user_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  'Admin',
  'The caller is the Admin of the new company'
);

-- A caller who already has a company keeps it.
CREATE TEMP TABLE frank_company AS
  SELECT company_id FROM public.company_users WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000002';
GRANT SELECT ON frank_company TO authenticated;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-000000000002", "role": "authenticated"}', true);

SELECT is(
  public.ensure_my_company(),
  (SELECT company_id FROM frank_company),
  'A caller who already has a company gets that company back'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000002'),
  1::bigint,
  'A caller who already has a company does not get a second one'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-000000000003", "role": "authenticated"}', true);

SELECT isnt(public.ensure_my_company(), NULL::uuid, 'A caller with a blank first name still gets a company');

RESET ROLE;

SELECT is(
  (SELECT c.name FROM public.companies c JOIN public.company_users cu ON cu.company_id = c.id
    WHERE cu.user_id = 'eeeeeeee-0000-0000-0000-000000000003'),
  'My company',
  'A blank first name gives the company the name My company'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-0000000000ff", "role": "authenticated"}', true);

SELECT is(
  public.ensure_my_company(),
  NULL::uuid,
  'A caller with no users row gets NULL and no company is created'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);

SELECT throws_ok(
  $$SELECT public.ensure_my_company()$$,
  '42501',
  NULL,
  'anon cannot call ensure_my_company()'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-000000000001", "role": "authenticated"}', true);

SELECT throws_ok(
  $$SELECT public.create_personal_company('eeeeeeee-0000-0000-0000-000000000001', 'Erin')$$,
  '42501',
  NULL,
  'authenticated cannot call create_personal_company() directly'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.company_users WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  1::bigint,
  'The refused direct call created nothing'
);

SELECT * FROM finish();
ROLLBACK;
