-- Test Suite: Cost Estimate Activity Logging
-- Tests for all triggers and functions related to cost estimate activity logging
-- Uses pgTAP framework for comprehensive testing

begin;
select plan(40);

DO $$
DECLARE
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_user2_id uuid := '88888888-8888-8888-8888-888888888888';
  v_credential2_id uuid := '99999999-9999-9999-9999-999999999999';
  v_project_id uuid := '33333333-3333-3333-3333-333333333333';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_estimate_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_item_id uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_file_id uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
BEGIN
  -- Setup test data
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user_id, v_credential_id, 'activity_log_user1@example.com', 'Activity', 'Log1', v_prof_role_id, now(), 'active', '{}', '+1');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user2_id, v_credential2_id, 'activity_log_user2@example.com', 'Activity', 'Log2', v_prof_role_id, now(), 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (v_project_id, 'Activity Log Test Project', v_user_id, now(), now(), 'active');
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost)
    VALUES (v_estimate_id, v_project_id, 'Activity Log Estimate', v_user_id, 'overall', 1000.00);
END $$;

-- Tests run as postgres role to bypass RLS, focusing on trigger logic only
-- The SECURITY DEFINER functions still work perfectly and can call auth.uid()

-- =============================================================
-- Test 1: Cost Estimate Creation logs activity
-- =============================================================
SELECT bag_eq(
  $$ SELECT activity FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_created' $$,
  $$ VALUES ('cost_estimation_created'::public.cost_estimation_activity_type_enum) $$,
  'Cost estimate creation creates log entry'
);

-- =============================================================
-- Test 2: Creation log has correct description
-- =============================================================
SELECT matches(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_created' LIMIT 1),
  'Cost estimate created: Activity Log Estimate',
  'Creation log description is correct'
);

-- =============================================================
-- Test 3: Rename activity logged with correct details
-- =============================================================
DO $$
BEGIN
  UPDATE cost_estimates SET estimate_name = 'Renamed Estimate' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_renamed'),
  1::bigint,
  'Cost estimate rename logged'
);

SELECT is(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_renamed' LIMIT 1),
  'Cost estimate renamed from "Activity Log Estimate" to "Renamed Estimate"',
  'Rename description includes old and new names'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_renamed' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Rename log has correct user_id'
);

SELECT is(
  (SELECT details->>'oldName' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_renamed' LIMIT 1),
  'Activity Log Estimate',
  'Rename details contains oldName'
);

SELECT is(
  (SELECT details->>'newName' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_renamed' LIMIT 1),
  'Renamed Estimate',
  'Rename details contains newName'
);

-- =============================================================
-- Test 4: Lock activity logged with correct details
-- =============================================================
DO $$
BEGIN
  UPDATE cost_estimates SET is_locked = true WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_locked'),
  1::bigint,
  'Cost estimate lock activity logged'
);


SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_locked' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Lock log has correct user_id'
);

-- =============================================================
-- Test 5: Unlock activity logged with correct details
-- =============================================================
DO $$
BEGIN
  UPDATE cost_estimates SET is_locked = false WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_unlocked'),
  1::bigint,
  'Cost estimate unlock activity logged'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_estimation_unlocked' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Unlock log has correct user_id'
);

-- =============================================================
-- Test 6: Cost File Upload logged with correct details
-- =============================================================
DO $$
BEGIN
  INSERT INTO cost_files (
    id, project_id, filename, content_type, file_size_bytes, uploaded_by_user_id, file_url, version
  ) VALUES (
    'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 
    '33333333-3333-3333-3333-333333333333'::uuid, 
    'test_file.pdf', 
    'application/pdf', 
    1024, 
    '11111111-1111-1111-1111-111111111111'::uuid, 
    'http://test.com/project/cost_files/test.pdf',
    '1.0'
  );
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_uploaded'),
  1::bigint,
  'Cost file upload logged to all estimates in project'
);

SELECT is(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_uploaded' LIMIT 1),
  'Cost file uploaded: test_file.pdf',
  'File upload description includes filename'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_uploaded' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'File upload log has correct user_id'
);

SELECT is(
  (SELECT details->>'fileName' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_uploaded' LIMIT 1),
  'test_file.pdf',
  'File upload details contains fileName'
);

SELECT is(
  (SELECT details->>'costFileId' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_uploaded' LIMIT 1),
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'File upload details contains fileId'
);

-- =============================================================
-- Test 7: Cost File Deletion logged with correct details
-- =============================================================
DO $$
BEGIN
  DELETE FROM cost_files WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_deleted'),
  1::bigint,
  'Cost file deletion logged'
);

SELECT is(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_deleted' LIMIT 1),
  'Cost file deleted: test_file.pdf',
  'File deletion description includes filename'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_deleted' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'File deletion log has correct user_id'
);

SELECT is(
  (SELECT details->>'fileName' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_deleted' LIMIT 1),
  'test_file.pdf',
  'File deletion details contains fileName'
);

SELECT is(
  (SELECT details->>'costFileId' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_file_deleted' LIMIT 1),
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'File deletion details contains fileId'
);

-- =============================================================
-- Test 8: Cost Item Addition logged with correct details
-- =============================================================
DO $$
BEGIN
  INSERT INTO cost_items (
    id, estimate_id, item_name, item_type, unit_price, quantity, unit_measurement, 
    calculation, item_total_cost, currency
  ) VALUES (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'Test Cost Item',
    'material',
    100.00,
    5,
    'units',
    '{}'::jsonb,
    500.00,
    'USD'
  );
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_added'),
  1::bigint,
  'Cost item addition logged'
);

SELECT is(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_added' LIMIT 1),
  'Cost item added: Test Cost Item',
  'Cost item added description is correct'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_added' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Cost item added log has correct user_id'
);

SELECT is(
  (SELECT details->>'costItemId' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_added' LIMIT 1),
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'Cost item added details contains costItemId'
);

SELECT is(
  (SELECT details->>'costItemType' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_added' LIMIT 1),
  'material',
  'Cost item added details contains costItemType'
);

-- =============================================================
-- Test 9: Cost Item Edit logged with correct details
-- =============================================================
DO $$
BEGIN
  UPDATE cost_items 
  SET item_name = 'Updated Cost Item', unit_price = 150.00
  WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited'),
  1::bigint,
  'Cost item edit logged'
);

SELECT is(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  'Cost item edited: Updated Cost Item',
  'Cost item edited description is correct'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Cost item edited log has correct user_id'
);

SELECT is(
  (SELECT details->>'costItemId' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'Cost item edited details contains costItemId'
);

SELECT is(
  (SELECT details->>'costItemType' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  'material',
  'Cost item edited details contains costItemType'
);

SELECT is(
  (SELECT (details->'editedFields'->'item_name'->>'oldValue') FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  'Test Cost Item',
  'Cost item edited details contains old item_name'
);

SELECT is(
  (SELECT (details->'editedFields'->'item_name'->>'newValue') FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  'Updated Cost Item',
  'Cost item edited details contains new item_name'
);

SELECT is(
  (SELECT (details->'editedFields'->'unit_price'->>'oldValue')::numeric FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  100.00,
  'Cost item edited details contains old unit_price'
);

SELECT is(
  (SELECT (details->'editedFields'->'unit_price'->>'newValue')::numeric FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_edited' LIMIT 1),
  150.00,
  'Cost item edited details contains new unit_price'
);

-- =============================================================
-- Test 10: Cost Item Removal logged with correct details
-- =============================================================
DO $$
BEGIN
  UPDATE cost_items SET deleted_at = now() WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
END $$;

SELECT is(
  (SELECT COUNT(*) FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_removed'),
  1::bigint,
  'Cost item removal logged'
);

SELECT is(
  (SELECT description FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_removed' LIMIT 1),
  'Cost item removed: Updated Cost Item',
  'Cost item removed description is correct'
);

SELECT is(
  (SELECT user_id FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_removed' LIMIT 1),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Cost item removed log has correct user_id'
);

SELECT is(
  (SELECT details->>'costItemId' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_removed' LIMIT 1),
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'Cost item removed details contains costItemId'
);

SELECT is(
  (SELECT details->>'costItemType' FROM cost_estimate_logs WHERE estimate_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND activity = 'cost_item_removed' LIMIT 1),
  'material',
  'Cost item removed details contains costItemType'
);

select * from finish();
rollback;
