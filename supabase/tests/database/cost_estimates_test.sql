begin;
select plan(15);

-- COST_ESTIMATES table: critical columns
SELECT has_column('public', 'cost_estimates', 'id', 'cost_estimates.id column exists');
SELECT col_type_is('public', 'cost_estimates', 'id', 'uuid', 'cost_estimates.id is uuid');
SELECT has_column('public', 'cost_estimates', 'project_id', 'cost_estimates.project_id column exists');
SELECT col_not_null('public', 'cost_estimates', 'estimate_name', 'cost_estimates.estimate_name is NOT NULL');
SELECT has_column('public', 'cost_estimates', 'markup_type', 'cost_estimates.markup_type column exists');
SELECT has_column('public', 'cost_estimates', 'total_cost', 'cost_estimates.total_cost column exists');
SELECT has_column('public', 'cost_estimates', 'is_locked', 'cost_estimates.is_locked column exists');
SELECT col_type_is('public', 'cost_estimates', 'is_locked', 'boolean', 'cost_estimates.is_locked is boolean');
SELECT has_column('public', 'cost_estimates', 'created_at', 'cost_estimates.created_at column exists');
SELECT has_column('public', 'cost_estimates', 'creator_user_id', 'cost_estimates.creator_user_id column exists');
SELECT has_column('public', 'cost_estimates', 'deleted_at', 'cost_estimates.deleted_at column exists');
SELECT col_type_is('public', 'cost_estimates', 'deleted_at', 'timestamp with time zone', 'cost_estimates.deleted_at is timestamp');

-- Data insertion test (with rollback)
DO $$
DECLARE
  user_id uuid := '11111111-1111-1111-1111-111111111111';
  project_id uuid := '33333333-3333-3333-3333-333333333333';
  credential_id uuid := '22222222-2222-2222-2222-222222222222';
  role_id uuid := '66666666-6666-6666-6666-666666666666';
BEGIN
  -- Setup: Insert user and project
  INSERT INTO professional_roles (id, name) VALUES (role_id, 'Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code) 
    VALUES (user_id, credential_id, 'cost_test@example.com', 'Cost', 'Test', role_id, now(), 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status) 
    VALUES (project_id, 'Cost Test Project', user_id, now(), now(), 'active');
  
  -- Insert cost estimate
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, is_locked)
    VALUES ('a50e8400-e29b-41d4-a716-446655440099', project_id, 'Test Estimate', user_id, 'overall', 500000.00, false);
END $$;
SELECT ok(true, 'Able to insert cost estimate with required fields');

SELECT isnt_empty(
  $$ SELECT * FROM cost_estimates WHERE id = 'a50e8400-e29b-41d4-a716-446655440099' AND deleted_at IS NULL $$,
  'deleted_at should be NULL after insert'
);

DELETE FROM cost_estimates WHERE id = 'a50e8400-e29b-41d4-a716-446655440099';


SELECT isnt_empty(
  $$ SELECT * FROM cost_estimates WHERE id = 'a50e8400-e29b-41d4-a716-446655440099' AND deleted_at IS NOT NULL $$,
  'Row should still exist in table with deleted_at set'
);

select * from finish();
rollback;
