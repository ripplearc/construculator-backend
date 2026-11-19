BEGIN;

-- Tests for CA-1306: your_rates ids are worked out from the rate's identity
-- (company, category, item_name_key, equipment_method, entry_label_key), so
-- every phone and this table give one rate one id, and two prices under two
-- labels get two ids. The examples below are the same table as
-- test/libraries/powersync/units/models/your_rate_id_examples.json in the app,
-- which the app tests run against its own YourRateId. The examples between the
-- GENERATED markers are written from that file by
-- scripts/your_rate_id_examples_sql.py, which also checks them (--check).
-- Run as postgres, which bypasses RLS and isolates the constraint layer.

SELECT plan(48);

INSERT INTO companies (id, email, phone, name)
VALUES
  ('77777777-7777-7777-7777-777777777777', 'rate-id-company@example.com', '+1-555-0017', 'Rate Id Test Company'),
  ('88888888-8888-8888-8888-888888888888', 'rate-id-company-b@example.com', '+1-555-0018', 'Rate Id Test Company B'),
  ('abcdefab-1234-5678-9abc-def012345678', 'rate-id-company-c@example.com', '+1-555-0019', 'Rate Id Test Company C');

DO $$
DECLARE
  v_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_company_role_id uuid := '66666666-6666-6666-6666-666666666666';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Rate Id Test Role');
  INSERT INTO roles (id, role_name, level, context_type)
    VALUES (v_company_role_id, 'Rate Id Test Company Role', 1, 'project');

  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
     'rate_id_member@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
  VALUES ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
          'rate_id_member@example.com', 'Rate', 'Member', v_role_id, now(), 'active', '{}', '+1');

  INSERT INTO company_users (user_id, company_id, role_id)
  VALUES ('11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777', v_company_role_id);
END $$;

CREATE FUNCTION pg_temp.name_key("name" text) RETURNS text LANGUAGE sql AS $$
  SELECT public.rate_key_lower(btrim(regexp_replace("name", '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085'))
$$;

CREATE FUNCTION pg_temp.label_key("label" text) RETURNS text LANGUAGE sql AS $$
  SELECT NULLIF(pg_temp.name_key("label"), '')
$$;

CREATE TEMP TABLE examples AS
SELECT * FROM (VALUES
-- BEGIN GENERATED EXAMPLES (scripts/your_rate_id_examples_sql.py)
  ('plain material', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, 'Concrete', NULL::equipment_pricing_method_enum, NULL, 'e8274668-ea4a-5305-8160-5e9334eb36a3'::uuid),
  ('case and outer spaces', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, '  CONCRETE  ', NULL::equipment_pricing_method_enum, NULL, 'e8274668-ea4a-5305-8160-5e9334eb36a3'::uuid),
  ('inner space runs and no-break space', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'Mini  \00a0excavator', NULL::equipment_pricing_method_enum, NULL, 'bc05a9d5-c42c-5425-bcad-6dbc61a2c6f7'::uuid),
  ('same name collapsed', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, 'mini excavator', NULL::equipment_pricing_method_enum, NULL, 'bc05a9d5-c42c-5425-bcad-6dbc61a2c6f7'::uuid),
  ('labor same name', '77777777-7777-7777-7777-777777777777'::uuid, 'labor'::cost_item_type_enum, 'Concrete', NULL::equipment_pricing_method_enum, NULL, '01da4b02-be8d-5a64-9df5-c50100de9a34'::uuid),
  ('other company', '88888888-8888-8888-8888-888888888888'::uuid, 'material'::cost_item_type_enum, 'Concrete', NULL::equipment_pricing_method_enum, NULL, 'ec6bbc47-56b9-52eb-982d-6786a61c03bb'::uuid),
  ('equipment day', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, NULL, '8d4e4cd4-c8a1-54ee-bdfc-650421a2e1e8'::uuid),
  ('equipment job', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'job'::equipment_pricing_method_enum, NULL, 'b81c791e-89b3-5b8c-bd58-7a1b1821d661'::uuid),
  ('equipment no method', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', NULL::equipment_pricing_method_enum, NULL, 'd9a0f9f6-4ee1-51e8-867f-98b0cfa1840c'::uuid),
  ('accented capital', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'\00c9clair', NULL::equipment_pricing_method_enum, NULL, '237a3f84-f073-5b82-9bc3-60c217d23d15'::uuid),
  ('cherokee capital kept', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'\13a0\13a1', NULL::equipment_pricing_method_enum, NULL, '54cc7838-8d14-503f-8627-33bb045fdeaf'::uuid),
  ('pipe in name', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, 'a|day', NULL::equipment_pricing_method_enum, NULL, 'c19f3528-bc11-5c4c-90a2-de6b8a617441'::uuid),
  ('ideographic space', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'A\3000B', NULL::equipment_pricing_method_enum, NULL, 'de2c51b0-fbc6-518b-9921-a966628964df'::uuid),
  ('line separator', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'A\2028B', NULL::equipment_pricing_method_enum, NULL, 'de2c51b0-fbc6-518b-9921-a966628964df'::uuid),
  ('greek final sigma', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'\039f\0394\039f\03a3', NULL::equipment_pricing_method_enum, NULL, 'b38c7d8f-6677-5f74-857b-260951a53587'::uuid),
  ('dotted capital i', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'\0130stanbul', NULL::equipment_pricing_method_enum, NULL, '1a90ff1d-3823-5bdb-a887-98805551d3f4'::uuid),
  ('upper-case company id', 'ABCDEFAB-1234-5678-9ABC-DEF012345678'::uuid, 'material'::cost_item_type_enum, 'Concrete', NULL::equipment_pricing_method_enum, NULL, '285a797a-4793-5def-aefd-1124ed3fc2ba'::uuid),
  ('tab and newline', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'A\0009\000aB', NULL::equipment_pricing_method_enum, NULL, 'de2c51b0-fbc6-518b-9921-a966628964df'::uuid),
  ('trailing next-line', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'Abc\0085', NULL::equipment_pricing_method_enum, NULL, 'a1c1919d-817d-51d7-9b6d-b942a539f9b0'::uuid),
  ('em space', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, U&'A\2003B', NULL::equipment_pricing_method_enum, NULL, 'de2c51b0-fbc6-518b-9921-a966628964df'::uuid),
  ('long name', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', NULL::equipment_pricing_method_enum, NULL, '1dbffaca-8ac4-59fe-b63d-c1d251bc4671'::uuid),
  ('equipment day with a label', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, 'With operator', '7b0eae4d-2e0f-50ed-bba5-1bf730149ab7'::uuid),
  ('label case and spaces', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, '  WITH   operator ', '7b0eae4d-2e0f-50ed-bba5-1bf730149ab7'::uuid),
  ('blank label is no label', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, '   ', '8d4e4cd4-c8a1-54ee-bdfc-650421a2e1e8'::uuid),
  ('other label', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, 'Supplier A', '0c33880a-23ca-5792-b2a8-0273b73de3ab'::uuid),
  ('pipe in label', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, 'a|job', '02c8dea2-bee7-57ca-8211-7ef33562b424'::uuid),
  ('non-ascii label', '77777777-7777-7777-7777-777777777777'::uuid, 'material'::cost_item_type_enum, 'Concrete', NULL::equipment_pricing_method_enum, U&'\00c9clair \0130stanbul', '3ae64bb3-0dac-59bb-9276-f715e2a40a1a'::uuid),
  ('pipes in a label make a name look like another rate: first', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift', 'day'::equipment_pricing_method_enum, 'a|job|b', '5ad4cfc6-1908-591a-81eb-db91462e3359'::uuid),
  ('pipes in a label make a name look like another rate: second', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'Scissor lift|day|a', 'job'::equipment_pricing_method_enum, 'b', '1bbef0ca-6536-5b37-9bcd-ed487d372332'::uuid),
  ('backslash at the end of a name', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'a\', 'day'::equipment_pricing_method_enum, 'b', '32f95f45-3025-50b0-b3cf-5adb92b9a927'::uuid),
  ('backslash at the start of a label', '77777777-7777-7777-7777-777777777777'::uuid, 'equipment'::cost_item_type_enum, 'a', 'day'::equipment_pricing_method_enum, '\b', 'ff1c51c2-7f11-53a5-8f7c-8ad7240e451e'::uuid)
-- END GENERATED EXAMPLES
) AS v(example, company_id, category, item_name, equipment_method, entry_label, expected_id);

-- ============================================================
-- Shared examples
-- ============================================================

SELECT is(
  public.your_rate_id(company_id, category, pg_temp.name_key(item_name), equipment_method, pg_temp.label_key(entry_label)),
  expected_id,
  'Shared example "' || example || '" gives its expected id'
) FROM examples ORDER BY example;

-- ============================================================
-- The check
-- ============================================================

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('e8274668-ea4a-5305-8160-5e9334eb36a3', '77777777-7777-7777-7777-777777777777', 'material', 'Concrete', 10, 'USD', now())$$,
  'A rate saved under the id its identity gives is accepted'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES (gen_random_uuid(), '77777777-7777-7777-7777-777777777777', 'material', 'Rebar', 10, 'USD', now())$$,
  '23514',
  NULL,
  'A rate saved under an id that is not its identity id is refused'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('e8274668-ea4a-5305-8160-5e9334eb36a3', '77777777-7777-7777-7777-777777777777', 'material', '  CONCRETE ', 20, 'USD', now())$$,
  '23505',
  NULL,
  'The same rate typed with other case and spaces is the same row, so a plain insert is refused'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('e8274668-ea4a-5305-8160-5e9334eb36a3', '77777777-7777-7777-7777-777777777777', 'material', '  CONCRETE ', 20, 'USD', now())
    ON CONFLICT (id) DO UPDATE SET rate_amount = EXCLUDED.rate_amount$$,
  'The second phone''s upload of the same rate is accepted as an upsert on id'
);

SELECT results_eq(
  $$SELECT count(*)::int, max(rate_amount)::numeric FROM public.your_rates WHERE company_id = '77777777-7777-7777-7777-777777777777'$$,
  $$VALUES (1, 20.0000::numeric)$$,
  'Both uploads end as one row and the last upload wins'
);

SELECT lives_ok(
  $$UPDATE public.your_rates SET rate_amount = 30 WHERE id = 'e8274668-ea4a-5305-8160-5e9334eb36a3'$$,
  'An edit made after the clash finds the row by that id'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, equipment_method, entry_label, rate_amount, rate_currency, saved_at)
    SELECT DISTINCT ON (expected_id) expected_id, company_id, category, item_name, equipment_method, entry_label, 1, 'USD', now()
    FROM examples ORDER BY expected_id, example
    ON CONFLICT (id) DO NOTHING$$,
  'Every shared example is accepted under its expected id, so the stored item_name_key and entry_label_key give the same id as the examples'
);


-- ============================================================
-- Two prices for one name and method, told apart by the label
-- ============================================================

DELETE FROM public.your_rates WHERE company_id = '77777777-7777-7777-7777-777777777777';

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, equipment_method, rate_amount, rate_currency, saved_at)
    VALUES ('8d4e4cd4-c8a1-54ee-bdfc-650421a2e1e8', '77777777-7777-7777-7777-777777777777', 'equipment', 'Scissor lift', 'day', 250, 'USD', now())$$,
  'A saved rate with no label is accepted under its id'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, equipment_method, entry_label, rate_amount, rate_currency, saved_at)
    VALUES ('7b0eae4d-2e0f-50ed-bba5-1bf730149ab7', '77777777-7777-7777-7777-777777777777', 'equipment', 'Scissor lift', 'day', 'With operator', 320, 'USD', now())$$,
  'A second price for the same name and method under a label is accepted under its own id'
);

SELECT results_eq(
  $$SELECT count(*)::int, count(DISTINCT id)::int FROM public.your_rates WHERE company_id = '77777777-7777-7777-7777-777777777777' AND item_name = 'Scissor lift'$$,
  $$VALUES (2, 2)$$,
  'Both prices are kept as two rows with two ids'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, equipment_method, entry_label, rate_amount, rate_currency, saved_at)
    VALUES ('8d4e4cd4-c8a1-54ee-bdfc-650421a2e1e8', '77777777-7777-7777-7777-777777777777', 'equipment', 'Scissor lift', 'day', 'With operator', 400, 'USD', now())$$,
  '23514',
  NULL,
  'A labelled price under the unlabelled rate''s id is refused, because the id is not its own'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, equipment_method, entry_label, rate_amount, rate_currency, saved_at)
    VALUES ('7b0eae4d-2e0f-50ed-bba5-1bf730149ab7', '77777777-7777-7777-7777-777777777777', 'equipment', 'Scissor lift', 'day', '  WITH   operator ', 330, 'USD', now())
    ON CONFLICT (id) DO UPDATE SET rate_amount = EXCLUDED.rate_amount$$,
  'The same label typed with other case and spaces is the same row, so a second phone''s upsert is accepted'
);

SELECT results_eq(
  $$SELECT rate_amount FROM public.your_rates WHERE id = '7b0eae4d-2e0f-50ed-bba5-1bf730149ab7'$$,
  $$VALUES (330.0000::numeric)$$,
  'The upsert changed the labelled price and left the unlabelled one alone'
);

-- ============================================================
-- No id, and who may ask for an id
-- ============================================================

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'material', 'Rebar', 10, 'USD', now())$$,
  '23502',
  NULL,
  'An insert without an id fails with a not-null error, because the column has no random default'
);

SELECT is(
  has_function_privilege('anon', 'public.your_rate_id(uuid, public.cost_item_type_enum, text, public.equipment_pricing_method_enum, text)', 'execute'),
  false,
  'anon cannot run your_rate_id'
);

-- ============================================================
-- A company member's second phone, with RLS on
-- ============================================================

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": { "internal_user_id": "11111111-1111-1111-1111-111111111111" }
}', true);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (id, company_id, category, item_name, equipment_method, rate_amount, rate_currency, saved_at)
    VALUES ('8d4e4cd4-c8a1-54ee-bdfc-650421a2e1e8', '77777777-7777-7777-7777-777777777777', 'equipment', 'Scissor lift', 'day', 275, 'USD', now())
    ON CONFLICT (id) DO UPDATE SET rate_amount = EXCLUDED.rate_amount$$,
  'A company member''s second phone uploads the same rate as an upsert on its id'
);

SELECT results_eq(
  $$SELECT count(*)::int, max(rate_amount) FILTER (WHERE entry_label IS NULL) FROM public.your_rates WHERE item_name = 'Scissor lift'$$,
  $$VALUES (2, 275.0000::numeric)$$,
  'The member''s upsert ended as the same two rows, with the last upload''s price'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
