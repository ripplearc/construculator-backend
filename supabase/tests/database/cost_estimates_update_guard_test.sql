begin;
select plan(10);

DO $$
DECLARE
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_user2_id uuid := '88888888-8888-8888-8888-888888888888';
  v_credential2_id uuid := '99999999-9999-9999-9999-999999999999';
  v_project_id uuid := '33333333-3333-3333-3333-333333333333';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_admin_role_id uuid := '66666666-6666-6666-6666-666666666666';
  v_collab_role_id uuid := '77777777-7777-7777-7777-777777777777';
  v_user3_id uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_credential3_id uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  v_viewer_role_id uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_estimate_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user_id, v_credential_id, 'admin_guard@example.com', 'Admin', 'User', v_prof_role_id, now(), 'active', '{}', '+1');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user2_id, v_credential2_id, 'collab_guard@example.com', 'Collab', 'User', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (v_project_id, 'Guard Test Project', v_user_id, now(), now(), 'active');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user3_id, v_credential3_id, 'viewer_guard@example.com', 'Viewer', 'User', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_admin_role_id, 'TestAdmin', 4, 'project');
  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_collab_role_id, 'TestCollab', 2, 'project');
  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_viewer_role_id, 'TestViewer', 1, 'project');

  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_admin_role_id, id FROM permissions WHERE permission_key IN ('get_cost_estimations', 'edit_cost_estimation', 'lock_cost_estimation');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_collab_role_id, id FROM permissions WHERE permission_key IN ('get_cost_estimations', 'edit_cost_estimation');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_viewer_role_id, id FROM permissions WHERE permission_key IN ('get_cost_estimations');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_user_id, v_admin_role_id, 'joined', now());
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_user2_id, v_collab_role_id, 'joined', now());
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_user3_id, v_viewer_role_id, 'joined', now());

  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, is_locked)
    VALUES (v_estimate_id, v_project_id, 'Test Estimate', v_user_id, 'overall', 500000.00, false);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

-- =============================================================
-- Test 1: Immutable guard blocks creator_user_id change
-- =============================================================
SELECT throws_ok(
  $$ UPDATE cost_estimates SET creator_user_id = '00000000-0000-0000-0000-000000000000' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '42501',
  'Immutable columns on cost_estimates cannot be updated',
  'Trigger blocks creator_user_id change'
);

-- =============================================================
-- Test 2: Collaborator (no lock permission) cannot lock estimate
-- =============================================================
SELECT set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999"}', true);

SELECT throws_ok(
  $$ UPDATE cost_estimates SET is_locked = true WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '42501',
  'Insufficient permissions: lock_cost_estimation required to modify lock columns',
  'Collaborator cannot lock estimate'
);

-- =============================================================
-- Test 3: Admin can lock by setting is_locked = true
-- =============================================================
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

SELECT lives_ok(
  $$ UPDATE cost_estimates SET is_locked = true WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  'Admin can lock estimate by setting is_locked = true'
);

RESET ROLE;

-- =============================================================
-- Test 4: Trigger auto-populated locked_by_user_id from auth.uid()
-- =============================================================
SELECT is(
  (SELECT locked_by_user_id FROM cost_estimates WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'locked_by_user_id auto-set to current user id'
);

-- =============================================================
-- Test 5: Trigger auto-populated locked_at
-- =============================================================
SELECT isnt_empty(
  $$ SELECT locked_at FROM cost_estimates WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND locked_at IS NOT NULL $$,
  'locked_at auto-set to timestamp when locked'
);

-- =============================================================
-- Test 6: Admin can unlock by setting is_locked = false
-- =============================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

SELECT lives_ok(
  $$ UPDATE cost_estimates SET is_locked = false WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  'Admin can unlock by setting is_locked = false'
);

RESET ROLE;

-- =============================================================
-- Test 7: Unlock clears locked_by_user_id and locked_at
-- =============================================================
SELECT is_empty(
  $$ SELECT locked_by_user_id FROM cost_estimates WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND locked_by_user_id IS NOT NULL $$,
  'locked_by_user_id cleared after unlock'
);

-- =============================================================
-- Test 8: Collaborator can update estimate_name (allowed column)
-- =============================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999"}', true);

SELECT lives_ok(
  $$ UPDATE cost_estimates SET estimate_name = 'Renamed Estimate' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  'Collaborator can update estimate_name (allowed column)'
);

RESET ROLE;

-- =============================================================
-- Test 9: estimate_name actually changed after allowed edit
-- =============================================================
SELECT is(
  (SELECT estimate_name FROM cost_estimates WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Renamed Estimate',
  'estimate_name was actually updated'
);

-- =============================================================
-- Test 10: Viewer without edit_cost_estimation blocked by RLS
-- =============================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

UPDATE cost_estimates SET estimate_name = 'Should Not Change' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

RESET ROLE;

SELECT is(
  (SELECT estimate_name FROM cost_estimates WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Renamed Estimate',
  'RLS blocks viewer without edit_cost_estimation from updating'
);

select * from finish();
rollback;
