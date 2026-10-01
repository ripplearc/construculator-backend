begin;
select plan(33);

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
SELECT has_column('public', 'cost_items', 'delivery_fee_status', 'cost_items.delivery_fee_status column exists');
SELECT col_type_is('public', 'cost_items', 'delivery_fee_status', 'delivery_fee_status_enum', 'cost_items.delivery_fee_status is delivery_fee_status_enum');
SELECT has_column('public', 'cost_items', 'rate_status', 'cost_items.rate_status column exists');
SELECT col_type_is('public', 'cost_items', 'rate_status', 'rate_status_enum', 'cost_items.rate_status is rate_status_enum');

-- The enum values, and the numeric columns' precision/scale, are the wire
-- contract with the app (app#649): a renamed label or a widened/narrowed
-- numeric column would still pass every check above without this.
SELECT enum_has_labels('public', 'equipment_pricing_method_enum', ARRAY['day', 'job']);
SELECT enum_has_labels('public', 'delivery_fee_status_enum', ARRAY['unset', 'estimated', 'confirmed']);
SELECT enum_has_labels(
  'public', 'rate_status_enum',
  ARRAY['sample_rate_unverified', 'own_rate_confirmed', 'missing']
);
SELECT col_type_is('public', 'cost_items', 'duration', 'numeric(10,2)', 'cost_items.duration is numeric(10,2)');
SELECT col_type_is('public', 'cost_items', 'daily_rate', 'numeric(18,4)', 'cost_items.daily_rate is numeric(18,4)');
SELECT col_type_is('public', 'cost_items', 'job_amount', 'numeric(18,4)', 'cost_items.job_amount is numeric(18,4)');
SELECT col_type_is('public', 'cost_items', 'delivery_fee', 'numeric(18,4)', 'cost_items.delivery_fee is numeric(18,4)');

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
  delivery_fee, delivery_fee_status, rate_status, calculation, item_total_cost, currency
) VALUES (
  'c50e8400-e29b-41d4-a716-446655440002', 'a50e8400-e29b-41d4-a716-446655440098', 'equipment',
  'Mini Excavator', 'day', 5.0, 145.00, 85.00, 'confirmed', 'own_rate_confirmed', '{}', 810.00, 'USD'
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
  (SELECT delivery_fee_status::text FROM cost_items WHERE id = 'c50e8400-e29b-41d4-a716-446655440002'),
  'confirmed',
  'Equipment item round-trips delivery_fee_status'
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

select * from finish();
rollback;
