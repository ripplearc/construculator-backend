begin;
select plan(11);

SELECT has_column('public', 'cost_estimate_logs', 'id', 'cost_estimate_logs.id column exists');
SELECT col_type_is('public', 'cost_estimate_logs', 'id', 'uuid', 'cost_estimate_logs.id is uuid');
SELECT has_column('public', 'cost_estimate_logs', 'estimate_id', 'cost_estimate_logs.estimate_id column exists');
SELECT col_not_null('public', 'cost_estimate_logs', 'activity', 'cost_estimate_logs.activity is NOT NULL');
SELECT has_column('public', 'cost_estimate_logs', 'user_id', 'cost_estimate_logs.user_id column exists');
SELECT has_column('public', 'cost_estimate_logs', 'logged_at', 'cost_estimate_logs.logged_at column exists');
SELECT has_column('public', 'cost_estimate_logs', 'deleted_at', 'cost_estimate_logs.deleted_at column exists');
SELECT col_type_is('public', 'cost_estimate_logs', 'deleted_at', 'timestamp with time zone', 'cost_estimate_logs.deleted_at is timestamp');

DO $$
DECLARE
  user_id uuid := '11111111-1111-1111-1111-111111111111';
  project_id uuid := '33333333-3333-3333-3333-333333333333';
  estimate_id uuid := 'a50e8400-e29b-41d4-a716-446655440098';
  log_id uuid := 'b50e8400-e29b-41d4-a716-446655440001';
  credential_id uuid := '22222222-2222-2222-2222-222222222222';
  role_id uuid := '66666666-6666-6666-6666-666666666666';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (role_id, 'Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code) 
    VALUES (user_id, credential_id, 'log_test@example.com', 'Log', 'Test', role_id, now(), 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status) 
    VALUES (project_id, 'Log Test Project', user_id, now(), now(), 'active');
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, is_locked)
    VALUES (estimate_id, project_id, 'Test Estimate', user_id, 'overall', 500000.00, false);
  
  INSERT INTO cost_estimate_logs (id, estimate_id, activity, description, user_id, details, logged_at)
    VALUES (log_id, estimate_id, 'created', 'Test log entry', user_id, '{}', now());
END $$;
SELECT ok(true, 'Able to insert cost estimate log with required fields');

SELECT isnt_empty(
  $$ SELECT * FROM cost_estimate_logs WHERE id = 'b50e8400-e29b-41d4-a716-446655440001' AND deleted_at IS NULL $$,
  'deleted_at should be NULL after insert'
);

DELETE FROM cost_estimate_logs WHERE id = 'b50e8400-e29b-41d4-a716-446655440001';

SELECT isnt_empty(
  $$ SELECT * FROM cost_estimate_logs WHERE id = 'b50e8400-e29b-41d4-a716-446655440001' AND deleted_at IS NOT NULL $$,
  'Row should still exist in table with deleted_at set'
);

select * from finish();
rollback;
