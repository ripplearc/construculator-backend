BEGIN;


SELECT plan(5);

-- =============================================================================
-- 1. Function Existence
-- =============================================================================
SELECT has_function(
  'public',
  'custom_access_token_hook',
  ARRAY['jsonb'],
  'custom_access_token_hook function exists'
);

-- =============================================================================
-- 2. Test: Original claims are preserved
-- =============================================================================
DO $$
DECLARE
  test_event JSONB;
  result JSONB;
BEGIN
  test_event := jsonb_build_object(
    'user_id', 'ffffffff-ffff-ffff-ffff-000000000000',
    'claims', jsonb_build_object(
      'sub', 'ffffffff-ffff-ffff-ffff-000000000000',
      'email', 'test@example.com',
      'role', 'authenticated'
    )
  );

  result := public.custom_access_token_hook(test_event);

  -- Function should at minimum return the claims object
  IF NOT (result ? 'claims') THEN
    RAISE EXCEPTION 'Result must contain claims key';
  END IF;

  -- Original claims should be preserved
  IF result->'claims'->>'sub' != 'ffffffff-ffff-ffff-ffff-000000000000' THEN
    RAISE EXCEPTION 'Sub claim should be preserved';
  END IF;
END $$;
SELECT ok(true, 'Function returns valid structure and preserves claims');

-- =============================================================================
-- 3. Test: app_metadata is created when missing
-- =============================================================================
DO $$
DECLARE
  test_event JSONB;
  result JSONB;
BEGIN
  -- Test with claims that have NO app_metadata (common for first login)
  test_event := jsonb_build_object(
    'user_id', 'ffffffff-ffff-ffff-ffff-000000000000',
    'claims', jsonb_build_object(
      'sub', 'ffffffff-ffff-ffff-ffff-000000000000',
      'email', 'test@example.com'
      -- Deliberately no app_metadata
    )
  );

  result := public.custom_access_token_hook(test_event);

  -- app_metadata should be created
  IF NOT (result->'claims' ? 'app_metadata') THEN
    RAISE EXCEPTION 'app_metadata should be created when missing. Got: %', result::text;
  END IF;

  -- projects should be within app_metadata
  IF NOT (result->'claims'->'app_metadata' ? 'projects') THEN
    RAISE EXCEPTION 'projects should be within app_metadata. Got: %', (result->'claims'->'app_metadata')::text;
  END IF;

  -- projects should be an object (even if empty for non-existent user)
  IF jsonb_typeof(result->'claims'->'app_metadata'->'projects') != 'object' THEN
    RAISE EXCEPTION 'projects should be an object. Got type: %',
      jsonb_typeof(result->'claims'->'app_metadata'->'projects');
  END IF;

  -- Original claims should still be preserved
  IF result->'claims'->>'email' != 'test@example.com' THEN
    RAISE EXCEPTION 'Original claims should be preserved';
  END IF;
END $$;
SELECT ok(true, 'Creates app_metadata.projects structure when app_metadata is missing');

-- =============================================================================
-- 4. Test: Existing app_metadata fields are preserved
-- =============================================================================
DO $$
DECLARE
  test_event JSONB;
  result JSONB;
BEGIN
  -- Test with claims that already have app_metadata with other fields
  test_event := jsonb_build_object(
    'user_id', 'ffffffff-ffff-ffff-ffff-000000000000',
    'claims', jsonb_build_object(
      'sub', 'ffffffff-ffff-ffff-ffff-000000000000',
      'email', 'test@example.com',
      'app_metadata', jsonb_build_object(
        'provider', 'email',
        'custom_field', 'custom_value'
      )
    )
  );

  result := public.custom_access_token_hook(test_event);

  -- app_metadata should exist
  IF NOT (result->'claims' ? 'app_metadata') THEN
    RAISE EXCEPTION 'app_metadata should exist';
  END IF;

  -- projects should be added to app_metadata
  IF NOT (result->'claims'->'app_metadata' ? 'projects') THEN
    RAISE EXCEPTION 'projects should be added to app_metadata';
  END IF;

  -- Existing app_metadata fields should be preserved
  IF result->'claims'->'app_metadata'->>'provider' != 'email' THEN
    RAISE EXCEPTION 'Existing app_metadata.provider should be preserved. Got: %',
      result->'claims'->'app_metadata'->>'provider';
  END IF;

  IF result->'claims'->'app_metadata'->>'custom_field' != 'custom_value' THEN
    RAISE EXCEPTION 'Existing app_metadata.custom_field should be preserved. Got: %',
      result->'claims'->'app_metadata'->>'custom_field';
  END IF;
END $$;
SELECT ok(true, 'Preserves existing app_metadata fields when adding projects');

-- =============================================================================
-- 5. Test: End-to-end test with real user and project memberships
-- =============================================================================
DO $$
DECLARE
  test_credential_id UUID := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  test_user_id UUID := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  test_project_id UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  test_role_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  test_prof_role_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  perm_get_id UUID;
  perm_add_id UUID;
  perm_edit_id UUID;
  test_event JSONB;
  result JSONB;
  expected_permissions JSONB;
  actual_permissions JSONB;
BEGIN
  -- Get existing permission IDs
  SELECT id INTO perm_get_id FROM permissions WHERE permission_key = 'get_cost_estimations';
  SELECT id INTO perm_add_id FROM permissions WHERE permission_key = 'add_cost_estimation';
  SELECT id INTO perm_edit_id FROM permissions WHERE permission_key = 'edit_cost_estimation';

  -- Setup: Create a real user with project membership and permissions
  INSERT INTO professional_roles (id, name) VALUES (test_prof_role_id, 'Test Professional Role');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (test_user_id, test_credential_id, 'hook_test@example.com', 'Hook', 'Test', test_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (test_project_id, 'Hook Test Project', test_user_id, now(), now(), 'active');

  -- Create role with specific permissions
  INSERT INTO roles (id, role_name, level, description, context_type)
    VALUES (test_role_id, 'Test Role', 1, 'Test role for hook testing', 'project');

  -- Associate existing permissions with role
  INSERT INTO role_permissions (role_id, permission_id) VALUES
    (test_role_id, perm_get_id),
    (test_role_id, perm_add_id),
    (test_role_id, perm_edit_id);

  -- Add user to project with role
  INSERT INTO project_members (user_id, project_id, role_id, membership_status, joined_at)
    VALUES (test_user_id, test_project_id, test_role_id, 'joined', now());

  -- Now test the hook with this real user
  test_event := jsonb_build_object(
    'user_id', test_credential_id::text,
    'claims', jsonb_build_object(
      'sub', test_credential_id::text,
      'email', 'hook_test@example.com'
    )
  );

  result := public.custom_access_token_hook(test_event);

  -- Verify the structure exists
  IF NOT (result->'claims'->'app_metadata' ? 'projects') THEN
    RAISE EXCEPTION 'app_metadata.projects should exist. Got: %', result::text;
  END IF;

  -- Verify the project ID is in the projects object
  IF NOT (result->'claims'->'app_metadata'->'projects' ? test_project_id::text) THEN
    RAISE EXCEPTION 'Project ID % should be in projects. Got: %',
      test_project_id::text,
      (result->'claims'->'app_metadata'->'projects')::text;
  END IF;

  -- Get actual permissions for the project
  actual_permissions := result->'claims'->'app_metadata'->'projects'->(test_project_id::text);

  -- Verify all three permissions are present
  IF NOT (actual_permissions ? 'add_cost_estimation') THEN
    RAISE EXCEPTION 'Should have add_cost_estimation permission. Got: %', actual_permissions::text;
  END IF;

  IF NOT (actual_permissions ? 'edit_cost_estimation') THEN
    RAISE EXCEPTION 'Should have edit_cost_estimation permission. Got: %', actual_permissions::text;
  END IF;

  IF NOT (actual_permissions ? 'get_cost_estimations') THEN
    RAISE EXCEPTION 'Should have get_cost_estimations permission. Got: %', actual_permissions::text;
  END IF;

  -- Verify permissions are sorted (the query uses ORDER BY)
  expected_permissions := '["add_cost_estimation", "edit_cost_estimation", "get_cost_estimations"]'::jsonb;
  IF actual_permissions != expected_permissions THEN
    RAISE EXCEPTION 'Permissions should be sorted. Expected: %, Got: %',
      expected_permissions::text,
      actual_permissions::text;
  END IF;

  -- Verify internal_user_id is present in app_metadata
  IF NOT (result->'claims'->'app_metadata' ? 'internal_user_id') THEN
    RAISE EXCEPTION 'app_metadata.internal_user_id should exist. Got: %',
      (result->'claims'->'app_metadata')::text;
  END IF;

  -- Verify internal_user_id matches the test user's ID
  IF (result->'claims'->'app_metadata'->>'internal_user_id')::uuid != test_user_id THEN
    RAISE EXCEPTION 'internal_user_id should match user ID. Expected: %, Got: %',
      test_user_id::text,
      (result->'claims'->'app_metadata'->>'internal_user_id')::text;
  END IF;

END $$;
SELECT ok(true, 'Hook correctly injects real user permissions for project memberships');

SELECT * FROM finish();
ROLLBACK;
