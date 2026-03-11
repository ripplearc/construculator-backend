begin;
select plan(5);

-- 1. Setup Data
DO $$
DECLARE
  u_id uuid := '11111111-1111-1111-1111-111111111111';
  p_id uuid := '22222222-2222-2222-2222-222222222222';
  e_id uuid := '33333333-3333-3333-3333-333333333333';
  r_id uuid := '44444444-4444-4444-4444-444444444444';
  c_id uuid := '55555555-5555-5555-5555-555555555555';
BEGIN
  -- Prerequisites
  INSERT INTO professional_roles (id, name) VALUES (r_id, 'Tester');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code) 
    VALUES (u_id, c_id, 'tester@example.com', 'Test', 'User', r_id, now(), 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status) 
    VALUES (p_id, 'Test Project', u_id, now(), now(), 'active');
  
  -- Create Parent Estimate
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost)
    VALUES (e_id, p_id, 'Cascade Test Estimate', u_id, 'overall', 1000.00);

  -- Create Children
  INSERT INTO cost_items (estimate_id, item_type, item_name, calculation, item_total_cost, currency)
    VALUES (e_id, 'labor', 'Test Item', '{}', 500.00, 'KSH');
  
  INSERT INTO cost_estimate_logs (estimate_id, activity, description, user_id, details)
    VALUES (e_id, 'cost_estimation_created', 'Test log', u_id, '{}');

  INSERT INTO user_favorites (user_id, favoritable_type, cost_estimate_id)
    VALUES (u_id, 'cost_estimate', e_id);

  INSERT INTO attachments (cost_estimate_id, project_id, uploaded_by_user_id, attachment_parent_type, attachment_type, file_url, status)
    VALUES (e_id, p_id, u_id, 'CostEstimate', 'Photo', 'http://test.com', 'active');
END $$;
SELECT ok(true, 'Setup data created successfully');

-- 2. Test Soft Delete Trigger
UPDATE cost_estimates SET deleted_at = now() WHERE id = '33333333-3333-3333-3333-333333333333';

SELECT isnt_empty(
  $$ SELECT * FROM cost_items WHERE estimate_id = '33333333-3333-3333-3333-333333333333' AND deleted_at IS NOT NULL $$,
  'Cost items should be soft-deleted when estimate is soft-deleted'
);

SELECT isnt_empty(
  $$ SELECT * FROM cost_estimate_logs WHERE estimate_id = '33333333-3333-3333-3333-333333333333' AND deleted_at IS NOT NULL $$,
  'Cost estimate logs should be soft-deleted when estimate is soft-deleted'
);

SELECT isnt_empty(
  $$ SELECT * FROM attachments WHERE cost_estimate_id = '33333333-3333-3333-3333-333333333333' AND status = 'inactive' $$,
  'Attachments should be marked inactive when estimate is soft-deleted'
);

SELECT is_empty(
  $$ SELECT * FROM user_favorites WHERE cost_estimate_id = '33333333-3333-3333-3333-333333333333' $$,
  'User favorites should be physically deleted (per trigger logic) when estimate is soft-deleted'
);

select * from finish();
rollback;
