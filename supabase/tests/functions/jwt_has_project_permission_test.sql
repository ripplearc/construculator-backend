BEGIN;

-- Test jwt_has_project_permission function
-- This function checks if a user has a specific permission for a project by reading JWT claims

SELECT plan(9);

-- =============================================================================
-- 1. Function Existence
-- =============================================================================
SELECT has_function(
  'public',
  'jwt_has_project_permission',
  ARRAY['uuid', 'text'],
  'jwt_has_project_permission function exists'
);

-- =============================================================================
-- 2. Test: Permission exists in JWT
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '550e8400-e29b-41d4-a716-446655440000';
  has_permission BOOLEAN;
BEGIN
  -- Set JWT claims with permissions
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000001",
    "app_metadata": {
      "projects": {
        "550e8400-e29b-41d4-a716-446655440000": ["get_cost_estimations", "edit_cost_estimation", "add_cost_estimation"]
      }
    }
  }', true);

  has_permission := jwt_has_project_permission(test_project_id, 'get_cost_estimations');

  IF NOT has_permission THEN
    RAISE EXCEPTION 'User should have get_cost_estimations permission';
  END IF;
END $$;
SELECT ok(true, 'Returns true when user has the permission');

-- =============================================================================
-- 3. Test: Permission does not exist in JWT
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '550e8400-e29b-41d4-a716-446655440000';
  has_permission BOOLEAN;
BEGIN
  -- Set JWT claims with permissions
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000002",
    "app_metadata": {
      "projects": {
        "550e8400-e29b-41d4-a716-446655440000": ["get_cost_estimations", "edit_cost_estimation"]
      }
    }
  }', true);

  has_permission := jwt_has_project_permission(test_project_id, 'delete_cost_estimation');

  IF has_permission THEN
    RAISE EXCEPTION 'User should not have delete_cost_estimation permission';
  END IF;
END $$;
SELECT ok(true, 'Returns false when user lacks the permission');

-- =============================================================================
-- 4. Test: Project not in JWT claims
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '7c9e6679-7425-40de-944b-e07fc1f90ae7';
  has_permission BOOLEAN;
BEGIN
  -- Set JWT claims without the project
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000003",
    "app_metadata": {
      "projects": {
        "550e8400-e29b-41d4-a716-446655440000": ["get_cost_estimations"]
      }
    }
  }', true);

  has_permission := jwt_has_project_permission(test_project_id, 'get_cost_estimations');

  IF has_permission THEN
    RAISE EXCEPTION 'User should not have access to project not in claims';
  END IF;
END $$;
SELECT ok(true, 'Returns false when project is not in JWT claims');

-- =============================================================================
-- 5. Test: Empty projects object in JWT
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '550e8400-e29b-41d4-a716-446655440000';
  has_permission BOOLEAN;
BEGIN
  -- Set JWT claims with empty projects
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000004",
    "app_metadata": {
      "projects": {}
    }
  }', true);

  has_permission := jwt_has_project_permission(test_project_id, 'get_cost_estimations');

  IF has_permission THEN
    RAISE EXCEPTION 'User should not have permission with empty projects';
  END IF;
END $$;
SELECT ok(true, 'Returns false when projects object is empty');

-- =============================================================================
-- 6. Test: No app_metadata in JWT
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '550e8400-e29b-41d4-a716-446655440000';
  has_permission BOOLEAN;
BEGIN
  -- Set JWT claims without app_metadata
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000005",
    "email": "test@example.com"
  }', true);

  has_permission := jwt_has_project_permission(test_project_id, 'get_cost_estimations');

  IF has_permission THEN
    RAISE EXCEPTION 'User should not have permission without app_metadata';
  END IF;
END $$;
SELECT ok(true, 'Returns false when app_metadata is missing');

-- =============================================================================
-- 7. Test: Multiple permissions check
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '550e8400-e29b-41d4-a716-446655440000';
BEGIN
  -- Set JWT claims with multiple permissions
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000006",
    "app_metadata": {
      "projects": {
        "550e8400-e29b-41d4-a716-446655440000": [
          "get_cost_estimations",
          "add_cost_estimation",
          "edit_cost_estimation",
          "delete_cost_estimation",
          "lock_cost_estimation"
        ]
      }
    }
  }', true);

  -- Check all permissions
  IF NOT (
    jwt_has_project_permission(test_project_id, 'get_cost_estimations') AND
    jwt_has_project_permission(test_project_id, 'add_cost_estimation') AND
    jwt_has_project_permission(test_project_id, 'edit_cost_estimation') AND
    jwt_has_project_permission(test_project_id, 'delete_cost_estimation') AND
    jwt_has_project_permission(test_project_id, 'lock_cost_estimation')
  ) THEN
    RAISE EXCEPTION 'User should have all listed permissions';
  END IF;
END $$;
SELECT ok(true, 'Correctly checks multiple permissions');

-- =============================================================================
-- 8. Test: Case sensitivity
-- =============================================================================
DO $$
DECLARE
  test_project_id UUID := '550e8400-e29b-41d4-a716-446655440000';
  has_permission BOOLEAN;
BEGIN
  -- Set JWT claims with permissions
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000007",
    "app_metadata": {
      "projects": {
        "550e8400-e29b-41d4-a716-446655440000": ["get_cost_estimations"]
      }
    }
  }', true);

  -- Check with different case (should fail)
  has_permission := jwt_has_project_permission(test_project_id, 'GET_COST_ESTIMATIONS');

  IF has_permission THEN
    RAISE EXCEPTION 'Permission check should be case-sensitive';
  END IF;
END $$;
SELECT ok(true, 'Permission check is case-sensitive');

-- =============================================================================
-- 9. Test: Multiple projects in JWT
-- =============================================================================
DO $$
DECLARE
  project_1 UUID := '550e8400-e29b-41d4-a716-446655440000';
  project_2 UUID := '7c9e6679-7425-40de-944b-e07fc1f90ae7';
BEGIN
  -- Set JWT claims with multiple projects
  PERFORM set_config('request.jwt.claims', '{
    "sub": "ffffffff-ffff-ffff-ffff-000000000008",
    "app_metadata": {
      "projects": {
        "550e8400-e29b-41d4-a716-446655440000": ["get_cost_estimations", "add_cost_estimation"],
        "7c9e6679-7425-40de-944b-e07fc1f90ae7": ["get_cost_estimations", "lock_cost_estimation"]
      }
    }
  }', true);

  -- Check project 1 has add but not lock
  IF NOT jwt_has_project_permission(project_1, 'add_cost_estimation') THEN
    RAISE EXCEPTION 'Project 1 should have add_cost_estimation';
  END IF;

  IF jwt_has_project_permission(project_1, 'lock_cost_estimation') THEN
    RAISE EXCEPTION 'Project 1 should not have lock_cost_estimation';
  END IF;

  -- Check project 2 has lock but not add
  IF NOT jwt_has_project_permission(project_2, 'lock_cost_estimation') THEN
    RAISE EXCEPTION 'Project 2 should have lock_cost_estimation';
  END IF;

  IF jwt_has_project_permission(project_2, 'add_cost_estimation') THEN
    RAISE EXCEPTION 'Project 2 should not have add_cost_estimation';
  END IF;
END $$;
SELECT ok(true, 'Correctly handles multiple projects with different permissions');

SELECT * FROM finish();
ROLLBACK;
