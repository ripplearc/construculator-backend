BEGIN;

-- Tests for CA-596: global_search's filter_by_tag param, now applied to the
-- projects result via the project_tags pivot. Covers the NULL "no filter"
-- contract, exact-name matching, the RLS boundary on project_tags (tag
-- assignments follow project visibility), the estimations path being
-- unaffected, the interaction with the CA-752 date-range filter, and the
-- pivot's ON DELETE CASCADE behavior on both FK sides.

SELECT plan(12);

SELECT has_table('public', 'project_tags', 'project_tags pivot table exists');

SELECT has_index(
  'public',
  'project_tags',
  'project_tag_uq',
  ARRAY['project_id', 'tag_id'],
  'project_tags has the unique (project_id, tag_id) index'
);

DO $$
DECLARE
  v_viewer_id uuid := '11111111-1111-1111-1111-111111111111';
  v_viewer_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_admin_role_id uuid := '66666666-6666-6666-6666-666666666666';
  v_project_a uuid := '33333333-3333-3333-3333-333333333333';
  v_project_b uuid := '44444444-4444-4444-4444-444444444444';
  v_project_c uuid := '99999999-9999-9999-9999-999999999999';
  v_project_d uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  v_tag_concrete uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_tag_steel uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_tag_shared uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_tag_unused uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_estimate_a uuid := '77777777-7777-7777-7777-777777777777';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_viewer_id, v_viewer_credential_id, 'tag_filter_viewer@example.com', 'Tag', 'Viewer', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_admin_role_id, 'TestAdmin', 4, 'project');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_admin_role_id, id FROM permissions WHERE permission_key IN ('view_project', 'edit_project');

  -- Project B is backdated 60 days so the date-range interaction test can
  -- exclude it while the tag filter alone includes it. Project D is the RLS
  -- probe: the viewer is NOT a member, so neither the project nor its tag
  -- assignment may surface anywhere.
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES
      (v_project_a, 'tag filter project alpha', v_viewer_id, now() - interval '60 days', now() - interval '5 days', 'active'),
      (v_project_b, 'tag filter project beta', v_viewer_id, now() - interval '60 days', now() - interval '60 days', 'active'),
      (v_project_c, 'tag filter project gamma', v_viewer_id, now() - interval '60 days', now() - interval '5 days', 'active'),
      (v_project_d, 'tag filter project delta', v_viewer_id, now() - interval '60 days', now() - interval '5 days', 'active');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES
      (v_project_a, v_viewer_id, v_admin_role_id, 'joined', now()),
      (v_project_b, v_viewer_id, v_admin_role_id, 'joined', now()),
      (v_project_c, v_viewer_id, v_admin_role_id, 'joined', now());

  INSERT INTO tags (id, name)
    VALUES
      (v_tag_concrete, 'tagfilter-concrete'),
      (v_tag_steel, 'tagfilter-steel'),
      (v_tag_shared, 'tagfilter-shared'),
      (v_tag_unused, 'tagfilter-unused');

  -- A: concrete + shared. B: steel + shared. C: untagged. D: concrete but
  -- invisible to the viewer.
  INSERT INTO project_tags (project_id, tag_id)
    VALUES
      (v_project_a, v_tag_concrete),
      (v_project_a, v_tag_shared),
      (v_project_b, v_tag_steel),
      (v_project_b, v_tag_shared),
      (v_project_d, v_tag_concrete);

  -- One estimate on project A so the estimations path is exercised by the
  -- "estimations unaffected by filter_by_tag" assertion.
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, created_at, updated_at)
    VALUES (v_estimate_a, v_project_a, 'tag filter estimate alpha', v_viewer_id, 'overall', 1000.00, now() - interval '5 days', now() - interval '5 days');
END $$;

SET LOCAL ROLE authenticated;
-- cost_estimates RLS reads get_cost_estimations from JWT app_metadata claims
-- directly (jwt_has_project_permission), not from role_permissions/
-- project_members — project A must be listed here for the cost_estimates
-- fixture to be visible to this test's queries.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": {
    "projects": {
      "33333333-3333-3333-3333-333333333333": ["get_cost_estimations"]
    }
  }
}', true);

-- Test 3: NULL filter_by_tag returns all matching visible projects (no filter)
SELECT is(
  jsonb_array_length(global_search('tag filter', NULL, NULL, NULL, NULL, 'dashboard') -> 'projects'),
  3,
  'NULL filter_by_tag returns all matching projects'
);

-- Test 4: a tag narrows projects to those carrying it
SELECT is(
  jsonb_array_length(global_search('tag filter', 'tagfilter-concrete', NULL, NULL, NULL, 'dashboard') -> 'projects'),
  1,
  'filter_by_tag returns only projects carrying that tag'
);

-- Test 5: and it is the right project (not the RLS-hidden delta, which
-- carries the same tag)
SELECT is(
  global_search('tag filter', 'tagfilter-concrete', NULL, NULL, NULL, 'dashboard') -> 'projects' -> 0 ->> 'id',
  '33333333-3333-3333-3333-333333333333',
  'The concrete-tagged result is project alpha, not the RLS-hidden delta'
);

-- Test 6: a tag applied to no visible project returns zero projects
SELECT is(
  jsonb_array_length(global_search('tag filter', 'tagfilter-unused', NULL, NULL, NULL, 'dashboard') -> 'projects'),
  0,
  'A tag with no projects returns zero projects'
);

-- Test 7: a tag on two projects returns both
SELECT is(
  jsonb_array_length(global_search('tag filter', 'tagfilter-shared', NULL, NULL, NULL, 'dashboard') -> 'projects'),
  2,
  'A tag applied to two projects returns both'
);

-- Test 8: tag filter intersects with the date-range filter — beta carries
-- the shared tag but is backdated 60 days, so a from-bound of 10 days ago
-- leaves only alpha
SELECT is(
  jsonb_array_length(global_search('tag filter', 'tagfilter-shared', now() - interval '10 days', NULL, NULL, 'dashboard') -> 'projects'),
  1,
  'Tag filter combined with filter_by_date_from intersects on projects'
);

-- Test 9: filter_by_tag applies only to projects — the estimations result is
-- unaffected even when the filtered tag excludes the estimate's project
SELECT is(
  jsonb_array_length(global_search('tag filter', 'tagfilter-steel', NULL, NULL, NULL, 'estimation') -> 'estimations'),
  1,
  'filter_by_tag does not filter the estimations result'
);

-- Test 10: project_tags RLS — of the 5 pivot rows, the viewer sees only the
-- 4 on projects they can view; delta's assignment is hidden
SELECT is(
  (SELECT count(*)::int FROM project_tags),
  4,
  'project_tags SELECT is limited to rows on viewable projects'
);

RESET ROLE;

-- Test 11: deleting a project cascades to its pivot rows
DELETE FROM projects WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
SELECT is(
  (SELECT count(*)::int FROM project_tags WHERE project_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
  0,
  'Deleting a project cascades to project_tags'
);

-- Test 12: deleting a tag cascades to its pivot rows
DELETE FROM tags WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT is(
  (SELECT count(*)::int FROM project_tags WHERE tag_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  0,
  'Deleting a tag cascades to project_tags'
);

SELECT * FROM finish();

ROLLBACK;
