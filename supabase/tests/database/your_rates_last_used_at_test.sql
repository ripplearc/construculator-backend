BEGIN;

-- Tests for CA-1265: your_rates.last_used_at, the last time a cost line was
-- added with a saved rate. Covers the column shape, that PowerSync replicates
-- it, that NULL means "never added", that a company member can write it
-- under the existing update policy, that another company's row cannot be
-- written, and that changing a price leaves it alone.

SELECT plan(15);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_column('public', 'your_rates', 'last_used_at', 'your_rates has a last_used_at column');
SELECT col_type_is('public', 'your_rates', 'last_used_at', 'timestamp with time zone', 'last_used_at is timestamptz');
SELECT col_is_null('public', 'your_rates', 'last_used_at', 'last_used_at is nullable, so NULL can mean never added');
SELECT col_hasnt_default('public', 'your_rates', 'last_used_at', 'last_used_at has no default, the client stamps it');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'powersync'
      AND schemaname = 'public'
      AND tablename = 'your_rates'
      AND 'last_used_at' = ANY (attnames)
  ),
  'The powersync publication replicates last_used_at'
);

-- ============================================================
-- Fixtures: two companies, one member each
-- ============================================================

DO $$
DECLARE
  v_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_company_role_id uuid := '66666666-6666-6666-6666-666666666666';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Last Used Test Role');
  INSERT INTO roles (id, role_name, level, context_type)
    VALUES (v_company_role_id, 'Last Used Test Company Role', 1, 'project');

  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
     'last_used_owner@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated',
     'last_used_other@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     'last_used_owner@example.com', 'Last', 'Owner', v_role_id, now(), 'active', '{}', '+1'),
    ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
     'last_used_other@example.com', 'Last', 'Other', v_role_id, now(), 'active', '{}', '+1');

  INSERT INTO companies (id, email, phone, name)
  VALUES
    ('77777777-7777-7777-7777-777777777777', 'last-used-a@example.com', '+1-555-0011', 'Last Used Test Company A'),
    ('88888888-8888-8888-8888-888888888888', 'last-used-b@example.com', '+1-555-0012', 'Last Used Test Company B');

  INSERT INTO company_users (user_id, company_id, role_id)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777', v_company_role_id),
    ('33333333-3333-3333-3333-333333333333', '88888888-8888-8888-8888-888888888888', v_company_role_id);

  INSERT INTO your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
  VALUES ('88888888-8888-8888-8888-888888888888', 'equipment', 'Other company excavator', 250.0000, 'USD', now());
END $$;

-- ============================================================
-- NULL means never added; a stored value comes back unchanged
-- ============================================================

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Never added', 100.0000, 'USD', '2026-01-01T00:00:00Z')$$,
  'A rate saved without last_used_at is accepted'
);

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Never added'),
  NULL::timestamptz,
  'A rate saved without last_used_at reads NULL, meaning it was never added to an estimate'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Added once', 120.0000, 'USD', '2026-01-01T00:00:00Z', '2026-01-08T09:30:00Z')$$,
  'A rate saved with a last_used_at is accepted'
);

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Added once'),
  '2026-01-08T09:30:00Z'::timestamptz,
  'The stored last_used_at comes back exactly as the client stamped it'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Saved after its last use', 130.0000, 'USD', '2026-02-01T00:00:00Z', '2026-01-08T09:30:00Z')$$,
  'A saved_at later than last_used_at is accepted, because saving a new price after a use is valid'
);

-- ============================================================
-- RLS -- the existing update policy covers the new column
-- ============================================================

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": { "internal_user_id": "11111111-1111-1111-1111-111111111111" }
}', true);

SELECT lives_ok(
  $$UPDATE public.your_rates SET last_used_at = '2026-03-01T10:00:00Z' WHERE item_name = 'Never added'$$,
  'A company member can record a use on their own rate'
);

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Never added'),
  '2026-03-01T10:00:00Z'::timestamptz,
  'The member reads back the use they recorded'
);

SELECT lives_ok(
  $$UPDATE public.your_rates SET last_used_at = '2026-03-01T10:00:00Z' WHERE item_name = 'Other company excavator'$$,
  'Updating another company''s rate does not raise an error, it matches no rows'
);

RESET ROLE;

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Other company excavator'),
  NULL::timestamptz,
  'Another company''s last_used_at is unchanged by the member''s update'
);

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": { "internal_user_id": "11111111-1111-1111-1111-111111111111" }
}', true);

-- The app saves with an upsert that leaves last_used_at out.
INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Added once', 125.0000, 'USD', '2026-04-01T00:00:00Z')
ON CONFLICT (company_id, category, item_name_key, equipment_method, entry_label)
DO UPDATE SET rate_amount = EXCLUDED.rate_amount, saved_at = EXCLUDED.saved_at;

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Added once'),
  '2026-01-08T09:30:00Z'::timestamptz,
  'A save that sets a new price and saved_at but leaves last_used_at out keeps the recorded use'
);

SELECT * FROM finish();
ROLLBACK;
