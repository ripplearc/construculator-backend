begin;
select plan(63);

SELECT has_column('public', 'cost_items', 'id', 'cost_items.id column exists');
SELECT col_type_is('public', 'cost_items', 'id', 'uuid', 'cost_items.id is uuid');
SELECT has_column('public', 'cost_items', 'estimate_id', 'cost_items.estimate_id column exists');
SELECT col_not_null('public', 'cost_items', 'item_name', 'cost_items.item_name is NOT NULL');
SELECT has_column('public', 'cost_items', 'item_type', 'cost_items.item_type column exists');
SELECT has_column('public', 'cost_items', 'created_at', 'cost_items.created_at column exists');
SELECT has_column('public', 'cost_items', 'deleted_at', 'cost_items.deleted_at column exists');
SELECT col_type_is('public', 'cost_items', 'deleted_at', 'timestamp with time zone', 'cost_items.deleted_at is timestamp');

-- CA-1156: Equipment v2 columns
SELECT has_column('public', 'cost_items', 'pricing_method', 'cost_items.pricing_method column exists');
SELECT col_type_is('public', 'cost_items', 'pricing_method', 'equipment_pricing_method_enum', 'cost_items.pricing_method is equipment_pricing_method_enum');
SELECT has_column('public', 'cost_items', 'duration', 'cost_items.duration column exists');
SELECT has_column('public', 'cost_items', 'daily_rate', 'cost_items.daily_rate column exists');
SELECT has_column('public', 'cost_items', 'job_amount', 'cost_items.job_amount column exists');
SELECT has_column('public', 'cost_items', 'delivery_fee', 'cost_items.delivery_fee column exists');
SELECT has_column('public', 'cost_items', 'rate_status', 'cost_items.rate_status column exists');
SELECT col_type_is('public', 'cost_items', 'rate_status', 'rate_status_enum', 'cost_items.rate_status is rate_status_enum');

-- The enum values, and the numeric columns' precision/scale, are the wire
-- contract with the app (app#649): a renamed label or a widened/narrowed
-- numeric column would still pass every check above without this.
SELECT enum_has_labels('public', 'equipment_pricing_method_enum', ARRAY['day', 'job']);
SELECT enum_has_labels(
  'public', 'rate_status_enum',
  ARRAY['sample_rate_unverified', 'own_rate_unconfirmed', 'own_rate_confirmed', 'missing']
);
SELECT col_type_is('public', 'cost_items', 'duration', 'numeric(10,2)', 'cost_items.duration is numeric(10,2)');
SELECT col_type_is('public', 'cost_items', 'daily_rate', 'numeric(18,4)', 'cost_items.daily_rate is numeric(18,4)');
SELECT col_type_is('public', 'cost_items', 'job_amount', 'numeric(18,4)', 'cost_items.job_amount is numeric(18,4)');
SELECT col_type_is('public', 'cost_items', 'delivery_fee', 'numeric(18,4)', 'cost_items.delivery_fee is numeric(18,4)');

-- CA-1182: Material v2 columns
SELECT has_column('public', 'cost_items', 'waste_percent', 'cost_items.waste_percent column exists');
SELECT has_column('public', 'cost_items', 'quantity_provenance', 'cost_items.quantity_provenance column exists');
SELECT has_column('public', 'cost_items', 'calculator_formula', 'cost_items.calculator_formula column exists');
SELECT col_type_is('public', 'cost_items', 'waste_percent', 'numeric(5,2)', 'cost_items.waste_percent is numeric(5,2)');
SELECT col_type_is('public', 'cost_items', 'quantity_provenance', 'quantity_provenance_enum', 'cost_items.quantity_provenance is quantity_provenance_enum');
SELECT col_type_is('public', 'cost_items', 'calculator_formula', 'text', 'cost_items.calculator_formula is text');
SELECT enum_has_labels('public', 'quantity_provenance_enum', ARRAY['manual', 'from_calculator']);

DO $$
DECLARE
  user_id uuid := '11111111-1111-1111-1111-111111111111';
  project_id uuid := '33333333-3333-3333-3333-333333333333';
  estimate_id uuid := 'a50e8400-e29b-41d4-a716-446655440098';
  item_id uuid := 'c50e8400-e29b-41d4-a716-446655440001';
  credential_id uuid := '22222222-2222-2222-2222-222222222222';
  role_id uuid := '66666666-6666-6666-6666-666666666666';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (role_id, 'Test Role');
  -- CA-995: users.credential_id now FKs to auth.users(id), so a real auth
  -- account has to exist before it can be referenced here.
  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', credential_id, 'authenticated', 'authenticated',
    'item_test@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''
  );
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (user_id, credential_id, 'item_test@example.com', 'Item', 'Test', role_id, now(), 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status) 
    VALUES (project_id, 'Item Test Project', user_id, now(), now(), 'active');
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, is_locked)
    VALUES (estimate_id, project_id, 'Test Estimate', user_id, 'overall', 500000.00, false);
  
  INSERT INTO cost_items (id, estimate_id, item_type, item_name, calculation, item_total_cost, currency)
    VALUES (item_id, estimate_id, 'material', 'Test Item', '{}', 100.00, 'USD');
END $$;
SELECT ok(true, 'Able to insert cost item with required fields');

SELECT isnt_empty(
  $$ SELECT * FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440001' AND deleted_at IS NULL $$,
  'deleted_at should be NULL after insert'
);

DELETE FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440001';

SELECT isnt_empty(
  $$ SELECT * FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440001' AND deleted_at IS NOT NULL $$,
  'Row should still exist in table with deleted_at set'
);

-- CA-1156: day-priced equipment item round-trips its pricing fields
INSERT INTO cost_items (
  id, estimate_id, item_type, item_name, pricing_method, duration, daily_rate,
  delivery_fee, rate_status, calculation, item_total_cost, currency
) VALUES (
  'c50e8400-e29b-41d4-a716-446655440002', 'a50e8400-e29b-41d4-a716-446655440098', 'equipment',
  'Mini Excavator', 'day', 5.0, 145.00, 85.00, 'own_rate_confirmed', '{}', 810.00, 'USD'
);

SELECT is(
  (SELECT pricing_method::text FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440002'),
  'day',
  'Equipment item round-trips pricing_method'
);

SELECT is(
  (SELECT daily_rate FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440002'),
  145.00::numeric(18,4),
  'Equipment item round-trips daily_rate'
);

SELECT is(
  (SELECT rate_status::text FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440002'),
  'own_rate_confirmed',
  'Equipment item round-trips rate_status'
);

SELECT isnt_empty(
  $$ SELECT * FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440001'::uuid AND job_amount IS NULL AND pricing_method IS NULL $$,
  'A material item leaves the equipment-only columns NULL'
);

-- CA-1156: cost_items_duration_half_day_check only allows whole/half days
SELECT lives_ok(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, duration, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'equipment', 'Half day rental', 0.5, '{}', 10.00, 'USD') $$,
  'duration = 0.5 is allowed'
);

SELECT lives_ok(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, duration, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'equipment', 'A day and a half rental', 1.5, '{}', 10.00, 'USD') $$,
  'duration = 1.5 is allowed'
);

SELECT throws_like(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, duration, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'equipment', 'Third-of-a-day rental', 0.3, '{}', 10.00, 'USD') $$,
  '%cost_items_duration_half_day_check%',
  'duration = 0.3 violates the half-day check'
);

SELECT throws_like(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, duration, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'equipment', 'Zero-day rental', 0, '{}', 10.00, 'USD') $$,
  '%cost_items_duration_half_day_check%',
  'duration = 0 violates the half-day check'
);

SELECT throws_like(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, duration, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'equipment', 'Negative-day rental', -1, '{}', 10.00, 'USD') $$,
  '%cost_items_duration_half_day_check%',
  'duration = -1 violates the half-day check'
);

-- CA-1182: a material item round-trips its v2 fields, including the shared rate_status
INSERT INTO cost_items (
  id, estimate_id, item_type, item_name, waste_percent, quantity_provenance,
  calculator_formula, rate_status, calculation, item_total_cost, currency
) VALUES (
  'c50e8400-e29b-41d4-a716-446655440003', 'a50e8400-e29b-41d4-a716-446655440098', 'material',
  'Drywall sheet', 10.50, 'from_calculator', '47.24in x 94.49in', 'sample_rate_unverified', '{}', 156.00, 'USD'
);

SELECT is(
  (SELECT waste_percent FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440003'),
  10.50::numeric(5,2),
  'Material item round-trips waste_percent'
);

SELECT is(
  (SELECT quantity_provenance::text FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440003'),
  'from_calculator',
  'Material item round-trips quantity_provenance'
);

SELECT is(
  (SELECT calculator_formula FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440003'),
  '47.24in x 94.49in',
  'Material item round-trips calculator_formula'
);

SELECT is(
  (SELECT rate_status::text FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440003'),
  'sample_rate_unverified',
  'rate_status is shared: a material item stores it too'
);

SELECT throws_like(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, quantity_provenance, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'material', 'Bad label', 'fromCalculator', '{}', 10.00, 'USD') $$,
  '%quantity_provenance_enum%',
  'quantity_provenance rejects the camelCase label'
);

-- CA-1182: waste_percent stays between 0 and 100
SELECT lives_ok(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, waste_percent, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'material', 'No waste', 0, '{}', 10.00, 'USD'),
            ('a50e8400-e29b-41d4-a716-446655440098', 'material', 'All waste', 100, '{}', 10.00, 'USD') $$,
  'waste_percent accepts 0 and 100'
);

SELECT throws_like(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, waste_percent, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'material', 'Too much waste', 150, '{}', 10.00, 'USD') $$,
  '%cost_items_waste_percent_range_check%',
  'waste_percent rejects 150'
);

SELECT throws_like(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, waste_percent, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'material', 'Negative waste', -5, '{}', 10.00, 'USD') $$,
  '%cost_items_waste_percent_range_check%',
  'waste_percent rejects -5'
);

-- CA-1182: a second project with its own estimate and item, so the policies
-- are tested against the wrong project as well as the right one.
INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
  VALUES ('33333333-3333-3333-3333-333333333344', 'Other Project', '11111111-1111-1111-1111-111111111111', now(), now(), 'active');
INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, is_locked)
  VALUES ('a50e8400-e29b-41d4-a716-446655440099', '33333333-3333-3333-3333-333333333344', 'Other Estimate',
          '11111111-1111-1111-1111-111111111111', 'overall', 1000.00, false);
INSERT INTO cost_items (id, estimate_id, item_type, item_name, calculation, item_total_cost, currency)
  VALUES ('c50e8400-e29b-41d4-a716-446655440020', 'a50e8400-e29b-41d4-a716-446655440099', 'material', 'Other project item', '{}', 10.00, 'USD');

-- CA-1182: a signed-in user reads and writes cost items through RLS. The
-- checks above run as the table owner, which skips RLS.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": {
    "internal_user_id": "11111111-1111-1111-1111-111111111111",
    "projects": {
      "33333333-3333-3333-3333-333333333333": ["get_cost_estimations", "edit_cost_estimation"]
    }
  }
}', true);

SELECT lives_ok(
  $$ INSERT INTO cost_items (id, estimate_id, item_type, item_name, waste_percent, quantity_provenance, calculator_formula, calculation, item_total_cost, currency)
     VALUES ('c50e8400-e29b-41d4-a716-446655440010', 'a50e8400-e29b-41d4-a716-446655440098', 'material',
             'RLS drywall', 5, 'from_calculator', '10ft x 4ft', '{}', 20.00, 'USD') $$,
  'An editor can insert a Material item with the v2 columns'
);

SELECT is(
  (SELECT waste_percent FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010'),
  5.00::numeric(5,2),
  'An editor can read the item back'
);

SELECT lives_ok(
  $$ UPDATE cost_items SET waste_percent = 7 WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  'An editor can update the item'
);

SELECT is(
  (SELECT waste_percent FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010'),
  7.00::numeric(5,2),
  'The editor update is stored'
);

-- The editor holds permissions on project 1 only. Project 2 stays out of reach.
SELECT is_empty(
  $$ SELECT 1 FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440020' $$,
  'An editor of project 1 cannot read an item of project 2'
);

SELECT throws_ok(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440099', 'material', 'Wrong project item', '{}', 10.00, 'USD') $$,
  '42501',
  NULL,
  'An editor of project 1 cannot insert into an estimate of project 2'
);

SELECT throws_ok(
  $$ UPDATE cost_items SET estimate_id = 'a50e8400-e29b-41d4-a716-446655440099'
     WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  '42501',
  NULL,
  'An editor of project 1 cannot move an item to an estimate of project 2'
);

-- A viewer holds get_cost_estimations only.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": {
    "internal_user_id": "11111111-1111-1111-1111-111111111111",
    "projects": {
      "33333333-3333-3333-3333-333333333333": ["get_cost_estimations"]
    }
  }
}', true);

SELECT isnt_empty(
  $$ SELECT 1 FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  'A viewer can read the item'
);

SELECT throws_ok(
  $$ INSERT INTO cost_items (estimate_id, item_type, item_name, calculation, item_total_cost, currency)
     VALUES ('a50e8400-e29b-41d4-a716-446655440098', 'material', 'Viewer item', '{}', 10.00, 'USD') $$,
  '42501',
  NULL,
  'A viewer cannot insert an item'
);

UPDATE cost_items SET waste_percent = 9 WHERE id = 'c50e8400-e29b-41d4-a716-446655440010';
DELETE FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010';

-- A user with no permission on the project.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": {
    "internal_user_id": "11111111-1111-1111-1111-111111111111",
    "projects": {}
  }
}', true);

SELECT is_empty(
  $$ SELECT 1 FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  'A user with no permission on the project sees no items'
);

RESET ROLE;

SELECT results_eq(
  $$ SELECT waste_percent, deleted_at IS NULL FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  $$ VALUES (7.00::numeric(5,2), true) $$,
  'A viewer can neither update nor delete the item'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": {
    "internal_user_id": "11111111-1111-1111-1111-111111111111",
    "projects": {
      "33333333-3333-3333-3333-333333333333": ["get_cost_estimations", "edit_cost_estimation"]
    }
  }
}', true);

SELECT lives_ok(
  $$ DELETE FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  'An editor can delete the item'
);

SELECT is_empty(
  $$ SELECT 1 FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010' $$,
  'The deleted item is hidden from the editor'
);

RESET ROLE;

SELECT isnt(
  (SELECT deleted_at FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440010'),
  NULL::timestamptz,
  'The delete is a soft delete'
);

select * from finish();
rollback;
