BEGIN;


SELECT plan(4);

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

SELECT * FROM finish();
ROLLBACK;
