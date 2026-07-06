BEGIN;

-- Tests for CA-737: global_search's filter_by_owners uuid[] param, which
-- replaced the single-uuid filter_by_owner. Covers projects AND
-- cost_estimates symmetrically (both WHERE clauses carry the owner
-- predicate), plus the NULL / empty-array "no filter" contract and the
-- interaction with the CA-752 date-range filter.

SELECT plan(11);

SELECT has_function(
  'public',
  'global_search',
  ARRAY['text', 'text', 'timestamp with time zone', 'timestamp with time zone', 'uuid[]', 'text', 'integer', 'integer', 'integer', 'integer'],
  'global_search has the filter_by_owners uuid[] signature'
);

DO $$
DECLARE
  v_viewer_id uuid := '11111111-1111-1111-1111-111111111111';
  v_viewer_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_admin_role_id uuid := '66666666-6666-6666-6666-666666666666';
  v_owner_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_owner_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_owner_c uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_project_a uuid := '33333333-3333-3333-3333-333333333333';
  v_project_b uuid := '44444444-4444-4444-4444-444444444444';
  v_project_c uuid := '99999999-9999-9999-9999-999999999999';
  v_estimate_a uuid := '77777777-7777-7777-7777-777777777777';
  v_estimate_b uuid := '88888888-8888-8888-8888-888888888888';
  v_estimate_c uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');

  -- The viewer runs the searches; the three owners only create rows.
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES
      (v_viewer_id, v_viewer_credential_id, 'owner_filter_viewer@example.com', 'Owner', 'Viewer', v_prof_role_id, now(), 'active', '{}', '+1'),
      (v_owner_a, gen_random_uuid(), 'owner_filter_a@example.com', 'Owner', 'Alpha', v_prof_role_id, now(), 'active', '{}', '+1'),
      (v_owner_b, gen_random_uuid(), 'owner_filter_b@example.com', 'Owner', 'Beta', v_prof_role_id, now(), 'active', '{}', '+1'),
      (v_owner_c, gen_random_uuid(), 'owner_filter_c@example.com', 'Owner', 'Gamma', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_admin_role_id, 'TestAdmin', 4, 'project');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_admin_role_id, id FROM permissions WHERE permission_key IN ('view_project', 'edit_project');

  -- One project per owner. Owner B's rows are backdated 60 days so the
  -- date-range interaction test can exclude them while the owner filter
  -- alone includes them.
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES
      (v_project_a, 'owner filter project alpha', v_owner_a, now() - interval '60 days', now() - interval '5 days', 'active'),
      (v_project_b, 'owner filter project beta', v_owner_b, now() - interval '60 days', now() - interval '60 days', 'active'),
      (v_project_c, 'owner filter project gamma', v_owner_c, now() - interval '60 days', now() - interval '5 days', 'active');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES
      (v_project_a, v_viewer_id, v_admin_role_id, 'joined', now()),
      (v_project_b, v_viewer_id, v_admin_role_id, 'joined', now()),
      (v_project_c, v_viewer_id, v_admin_role_id, 'joined', now());

  -- One estimate per owner, mirroring the projects fixture split so the
  -- (structurally identical) cost_estimates owner predicate is actually
  -- exercised too.
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, created_at, updated_at)
    VALUES
      (v_estimate_a, v_project_a, 'owner filter estimate alpha', v_owner_a, 'overall', 1000.00, now() - interval '60 days', now() - interval '5 days'),
      (v_estimate_b, v_project_b, 'owner filter estimate beta', v_owner_b, 'overall', 2000.00, now() - interval '60 days', now() - interval '60 days'),
      (v_estimate_c, v_project_c, 'owner filter estimate gamma', v_owner_c, 'overall', 3000.00, now() - interval '60 days', now() - interval '5 days');
END $$;

SET LOCAL ROLE authenticated;
-- cost_estimates RLS reads get_cost_estimations from JWT app_metadata
-- claims directly (jwt_has_project_permission), not from role_permissions/
-- project_members — all three projects must be listed here for the
-- cost_estimates fixtures to be visible to this test's queries.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": {
    "projects": {
      "33333333-3333-3333-3333-333333333333": ["get_cost_estimations"],
      "44444444-4444-4444-4444-444444444444": ["get_cost_estimations"],
      "99999999-9999-9999-9999-999999999999": ["get_cost_estimations"]
    }
  }
}', true);

-- Test 1: NULL filter_by_owners returns all matching projects (no filter)
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, NULL, 'dashboard') -> 'projects'),
  3,
  'NULL filter_by_owners returns all matching projects'
);

-- Test 2: an empty array also means "no owner filter" — it must not
-- silently match zero rows (= ANY('{}') is always false without the guard)
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, ARRAY[]::uuid[], 'dashboard') -> 'projects'),
  3,
  'Empty filter_by_owners array returns all matching projects'
);

-- Test 3: a single owner narrows projects to that owner
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa']::uuid[], 'dashboard') -> 'projects'),
  1,
  'Single owner in filter_by_owners returns only that owner''s projects'
);

-- Test 4: two owners include both owners' projects and exclude the third
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[], 'dashboard') -> 'projects'),
  2,
  'Two owners in filter_by_owners return both owners'' projects only'
);

-- Tests 5-8: the same contract on the cost_estimates path via scope='estimation'

-- Test 5: NULL filter_by_owners returns all matching estimates
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, NULL, 'estimation') -> 'estimations'),
  3,
  'NULL filter_by_owners returns all matching cost estimates'
);

-- Test 6: empty array returns all matching estimates
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, ARRAY[]::uuid[], 'estimation') -> 'estimations'),
  3,
  'Empty filter_by_owners array returns all matching cost estimates'
);

-- Test 7: a single owner narrows estimates to that owner
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[], 'estimation') -> 'estimations'),
  1,
  'Single owner in filter_by_owners returns only that owner''s cost estimates'
);

-- Test 8: two owners include both owners' estimates and exclude the third
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, NULL, NULL, ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'cccccccc-cccc-cccc-cccc-cccccccccccc']::uuid[], 'estimation') -> 'estimations'),
  2,
  'Two owners in filter_by_owners return both owners'' cost estimates only'
);

-- Tests 9-10: owner filter intersects with the CA-752 date-range filter.
-- Owners A+B are selected, but owner B's rows are backdated 60 days, so a
-- from-bound of 10 days ago leaves only owner A's row on each path.

-- Test 9: projects path
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, now() - interval '10 days', NULL, ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[], 'dashboard') -> 'projects'),
  1,
  'Owner filter combined with filter_by_date_from intersects on projects'
);

-- Test 10: cost_estimates path
SELECT is(
  jsonb_array_length(global_search('owner filter', NULL, now() - interval '10 days', NULL, ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[], 'estimation') -> 'estimations'),
  1,
  'Owner filter combined with filter_by_date_from intersects on cost estimates'
);

RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
