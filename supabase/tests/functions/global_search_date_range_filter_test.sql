BEGIN;

-- Tests for CA-752: global_search's filter_by_date_from/filter_by_date_to
-- range filter. Assumes projects.updated_at is correctly maintained by the
-- trigger added in migration 36 (covered separately by
-- supabase/tests/database/projects_updated_at_trigger_test.sql).

SELECT plan(6);

SELECT has_function(
  'public',
  'global_search',
  ARRAY['text', 'text', 'timestamp with time zone', 'timestamp with time zone', 'uuid', 'text', 'integer', 'integer', 'integer', 'integer'],
  'global_search has the filter_by_date_from/filter_by_date_to signature'
);

DO $$
DECLARE
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_admin_role_id uuid := '66666666-6666-6666-6666-666666666666';
  v_project_old uuid := '33333333-3333-3333-3333-333333333333';
  v_project_new uuid := '44444444-4444-4444-4444-444444444444';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user_id, v_credential_id, 'date_filter@example.com', 'Date', 'Filter', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_admin_role_id, 'TestAdmin', 4, 'project');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_admin_role_id, id FROM permissions WHERE permission_key IN ('view_project', 'edit_project');

  -- "Old" project: updated_at backdated to 60 days ago, outside the test range.
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (v_project_old, 'date filter old project', v_user_id, now() - interval '60 days', now() - interval '60 days', 'active');

  -- "New" project: updated_at backdated to 5 days ago, inside the test range.
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (v_project_new, 'date filter new project', v_user_id, now() - interval '60 days', now() - interval '5 days', 'active');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_old, v_user_id, v_admin_role_id, 'joined', now());
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_new, v_user_id, v_admin_role_id, 'joined', now());
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

-- Test 1: neither bound set behaves like today's no-filter case (both projects returned)
SELECT is(
  jsonb_array_length(global_search('date filter', NULL, NULL, NULL, NULL, 'dashboard') -> 'projects'),
  2,
  'No date bounds returns all matching projects'
);

-- Test 2: only filter_by_date_from set excludes the old project
SELECT is(
  jsonb_array_length(global_search('date filter', NULL, now() - interval '10 days', NULL, NULL, 'dashboard') -> 'projects'),
  1,
  'filter_by_date_from alone excludes projects updated before it'
);

-- Test 3: only filter_by_date_to set excludes the new project
SELECT is(
  jsonb_array_length(global_search('date filter', NULL, NULL, now() - interval '10 days', NULL, 'dashboard') -> 'projects'),
  1,
  'filter_by_date_to alone excludes projects updated after it'
);

-- Test 4: both bounds set narrows to the project inside the range
SELECT is(
  jsonb_array_length(global_search('date filter', NULL, now() - interval '10 days', now() - interval '1 day', NULL, 'dashboard') -> 'projects'),
  1,
  'Both bounds set returns only the project inside the inclusive range'
);

-- Test 5: inverted range (from after to) raises a clear error instead of silently returning no rows
SELECT throws_ok(
  $$ SELECT global_search('date filter', NULL, now(), now() - interval '10 days', NULL, 'dashboard') $$,
  '22023',
  'filter_by_date_from must not be after filter_by_date_to',
  'Inverted date range raises a validation error'
);

RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
