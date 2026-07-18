BEGIN;

-- CA-807 (3/4): update_member_role RPC — permission check, two-sided level
-- rule, creator immutability, error paths.

SELECT plan(9);

-- Seeded role ids: Admin ...01 (4) / Manager ...02 (3) / Collaborator ...03 (2) / Viewer ...04 (1)

-- =============================================================================
-- Fixture: creator Admin, second Admin, Manager, Collaborator, Viewer
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'eeee5555-5555-5555-5555-555555555555';
  v_project_id uuid := 'eeee3333-3333-3333-3333-333333333333';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Role Change Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code) VALUES
    ('eeee1111-1111-1111-1111-111111111111', 'eeee1111-0000-0000-0000-000000000001', 'rc_creator@example.com', 'Creator', 'Admin', v_prof_role_id, 'active', '{}', '+1'),
    ('eeee1111-1111-1111-1111-222222222222', 'eeee1111-0000-0000-0000-000000000002', 'rc_admin2@example.com', 'Second', 'Admin', v_prof_role_id, 'active', '{}', '+1'),
    ('eeee1111-1111-1111-1111-333333333333', 'eeee1111-0000-0000-0000-000000000003', 'rc_manager@example.com', 'Mana', 'Ger', v_prof_role_id, 'active', '{}', '+1'),
    ('eeee1111-1111-1111-1111-444444444444', 'eeee1111-0000-0000-0000-000000000004', 'rc_collab@example.com', 'Colla', 'Borator', v_prof_role_id, 'active', '{}', '+1'),
    ('eeee1111-1111-1111-1111-555555555555', 'eeee1111-0000-0000-0000-000000000005', 'rc_viewer@example.com', 'View', 'Er', v_prof_role_id, 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id)
    VALUES (v_project_id, 'role change test project', 'eeee1111-1111-1111-1111-111111111111');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at) VALUES
    (v_project_id, 'eeee1111-1111-1111-1111-111111111111', 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now()),
    (v_project_id, 'eeee1111-1111-1111-1111-222222222222', 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now()),
    (v_project_id, 'eeee1111-1111-1111-1111-333333333333', 'a50e8400-e29b-41d4-a716-446655440002', 'joined', now()),
    (v_project_id, 'eeee1111-1111-1111-1111-444444444444', 'a50e8400-e29b-41d4-a716-446655440003', 'joined', now()),
    (v_project_id, 'eeee1111-1111-1111-1111-555555555555', 'a50e8400-e29b-41d4-a716-446655440004', 'joined', now());
END $$;

SET LOCAL ROLE authenticated;

-- =============================================================================
-- 1. Collaborator lacks update_member_role
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "eeee1111-0000-0000-0000-000000000004"}', true);
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-555555555555', 'a50e8400-e29b-41d4-a716-446655440003') $$,
  '42501', NULL,
  'Collaborator cannot change member roles'
);

-- =============================================================================
-- 2-3. Manager promotes Viewer to Collaborator
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "eeee1111-0000-0000-0000-000000000003"}', true);
SELECT lives_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-555555555555', 'a50e8400-e29b-41d4-a716-446655440003') $$,
  'Manager can promote a Viewer to Collaborator'
);

RESET ROLE;
SELECT is(
  (SELECT role_id FROM project_members
   WHERE project_id = 'eeee3333-3333-3333-3333-333333333333'
     AND user_id = 'eeee1111-1111-1111-1111-555555555555'),
  'a50e8400-e29b-41d4-a716-446655440003'::uuid,
  'The member now holds the Collaborator role'
);

-- =============================================================================
-- 4. Manager cannot promote beyond their own level (to Admin)
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "eeee1111-0000-0000-0000-000000000003"}', true);
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-555555555555', 'a50e8400-e29b-41d4-a716-446655440001') $$,
  '42501', NULL,
  'Manager cannot promote a member to Admin'
);

-- =============================================================================
-- 5. Manager cannot touch a member above their own level (an Admin)
-- =============================================================================
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-222222222222', 'a50e8400-e29b-41d4-a716-446655440004') $$,
  '42501', NULL,
  'Manager cannot demote an Admin'
);

-- =============================================================================
-- 6. Creator immutability (even for another Admin)
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "eeee1111-0000-0000-0000-000000000002"}', true);
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-111111111111', 'a50e8400-e29b-41d4-a716-446655440004') $$,
  '42501', NULL,
  'The creator''s membership cannot be role-changed'
);

-- =============================================================================
-- 7. Unknown membership -> P0002
-- =============================================================================
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       '00000000-0000-0000-0000-00000000dead', 'a50e8400-e29b-41d4-a716-446655440004') $$,
  'P0002', NULL,
  'Changing a non-member raises P0002'
);

-- =============================================================================
-- 8. Unknown role -> 22023
-- =============================================================================
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-555555555555', '00000000-0000-0000-0000-00000000dead') $$,
  '22023', NULL,
  'Changing to an unknown role raises 22023'
);

-- =============================================================================
-- 9. anon has no EXECUTE
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT update_member_role('eeee3333-3333-3333-3333-333333333333',
       'eeee1111-1111-1111-1111-555555555555', 'a50e8400-e29b-41d4-a716-446655440004') $$,
  '42501', NULL,
  'anon cannot execute update_member_role'
);
RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
