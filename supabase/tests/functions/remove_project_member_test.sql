BEGIN;

-- CA-807 (3/4): remove_project_member RPC — permission check, self-leave,
-- creator immutability, error paths.

SELECT plan(9);

-- Seeded role ids: Admin ...01 / Manager ...02 / Collaborator ...03 / Viewer ...04

-- =============================================================================
-- Fixture: creator Admin, Manager, Collaborator, Viewer
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'ffff5555-5555-5555-5555-555555555555';
  v_project_id uuid := 'ffff3333-3333-3333-3333-333333333333';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Remove Member Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code) VALUES
    ('ffff1111-1111-1111-1111-111111111111', 'ffff1111-0000-0000-0000-000000000001', 'rm_creator@example.com', 'Creator', 'Admin', v_prof_role_id, 'active', '{}', '+1'),
    ('ffff1111-1111-1111-1111-222222222222', 'ffff1111-0000-0000-0000-000000000002', 'rm_manager@example.com', 'Mana', 'Ger', v_prof_role_id, 'active', '{}', '+1'),
    ('ffff1111-1111-1111-1111-333333333333', 'ffff1111-0000-0000-0000-000000000003', 'rm_collab@example.com', 'Colla', 'Borator', v_prof_role_id, 'active', '{}', '+1'),
    ('ffff1111-1111-1111-1111-444444444444', 'ffff1111-0000-0000-0000-000000000004', 'rm_viewer@example.com', 'View', 'Er', v_prof_role_id, 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id)
    VALUES (v_project_id, 'remove member test project', 'ffff1111-1111-1111-1111-111111111111');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at) VALUES
    (v_project_id, 'ffff1111-1111-1111-1111-111111111111', 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now()),
    (v_project_id, 'ffff1111-1111-1111-1111-222222222222', 'a50e8400-e29b-41d4-a716-446655440002', 'joined', now()),
    (v_project_id, 'ffff1111-1111-1111-1111-333333333333', 'a50e8400-e29b-41d4-a716-446655440003', 'joined', now()),
    (v_project_id, 'ffff1111-1111-1111-1111-444444444444', 'a50e8400-e29b-41d4-a716-446655440004', 'joined', now());
END $$;

SET LOCAL ROLE authenticated;

-- =============================================================================
-- 1. Collaborator lacks remove_member (removing someone else)
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "ffff1111-0000-0000-0000-000000000003"}', true);
SELECT throws_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       'ffff1111-1111-1111-1111-444444444444') $$,
  '42501', NULL,
  'Collaborator cannot remove another member'
);

-- =============================================================================
-- 2-3. Self-leave is allowed without remove_member
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "ffff1111-0000-0000-0000-000000000004"}', true);
SELECT lives_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       'ffff1111-1111-1111-1111-444444444444') $$,
  'A Viewer can leave the project themselves'
);

RESET ROLE;
SELECT is(
  (SELECT count(*)::int FROM project_members
   WHERE project_id = 'ffff3333-3333-3333-3333-333333333333'
     AND user_id = 'ffff1111-1111-1111-1111-444444444444'),
  0,
  'The self-leaving member''s row is gone'
);

-- =============================================================================
-- 4-5. Manager removes a Collaborator
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "ffff1111-0000-0000-0000-000000000002"}', true);
SELECT lives_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       'ffff1111-1111-1111-1111-333333333333') $$,
  'Manager can remove a Collaborator'
);

RESET ROLE;
SELECT is(
  (SELECT count(*)::int FROM project_members
   WHERE project_id = 'ffff3333-3333-3333-3333-333333333333'
     AND user_id = 'ffff1111-1111-1111-1111-333333333333'),
  0,
  'The removed member''s row is gone'
);

-- =============================================================================
-- 6. The creator cannot be removed by anyone
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "ffff1111-0000-0000-0000-000000000002"}', true);
SELECT throws_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       'ffff1111-1111-1111-1111-111111111111') $$,
  '42501', NULL,
  'The creator cannot be removed by a Manager'
);

-- =============================================================================
-- 7. The creator cannot leave their own project
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "ffff1111-0000-0000-0000-000000000001"}', true);
SELECT throws_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       'ffff1111-1111-1111-1111-111111111111') $$,
  '42501', NULL,
  'The creator cannot leave their own project'
);

-- =============================================================================
-- 8. Removing a non-member -> P0002
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "ffff1111-0000-0000-0000-000000000002"}', true);
SELECT throws_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       '00000000-0000-0000-0000-00000000dead') $$,
  'P0002', NULL,
  'Removing a non-member raises P0002'
);

-- =============================================================================
-- 9. anon has no EXECUTE
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT remove_project_member('ffff3333-3333-3333-3333-333333333333',
       'ffff1111-1111-1111-1111-222222222222') $$,
  '42501', NULL,
  'anon cannot execute remove_project_member'
);
RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
