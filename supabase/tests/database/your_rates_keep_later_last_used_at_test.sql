BEGIN;

-- Tests for CA-1345: an update to your_rates.last_used_at keeps the later of
-- the stored and the incoming time. Covers the trigger's shape, an earlier
-- time, a later time, the first use, the exact boundary, other columns sent in
-- the same update, an empty time, an update that leaves the column out, two
-- rows in one statement, the upsert the phone sends (on id and on the unique
-- key), an empty time on both sides, a one microsecond difference, a time more
-- than 1 day ahead of the server on insert and on update, infinity, and a role
-- other than authenticated.

SELECT plan(32);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_function('public', 'keep_later_your_rates_last_used_at', 'The keep-later function exists');
SELECT has_trigger('public', 'your_rates', 'trigger_keep_later_your_rates_last_used_at', 'your_rates has the keep-later trigger');
SELECT trigger_is(
  'public', 'your_rates', 'trigger_keep_later_your_rates_last_used_at',
  'public', 'keep_later_your_rates_last_used_at',
  'The trigger runs the keep-later function'
);

-- ============================================================
-- Fixtures: one company with one member, rates stored as the
-- phones would have left them
-- ============================================================

DO $$
DECLARE
  v_role_id uuid := 'c1345000-0000-0000-0000-000000000001';
  v_company_role_id uuid := 'c1345000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Keep Later Test Role');
  INSERT INTO roles (id, role_name, level, context_type)
    VALUES (v_company_role_id, 'Keep Later Test Company Role', 1, 'project');

  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', 'c1345000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
     'keep_later_member@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
  VALUES
    ('c1345000-0000-0000-0000-000000000004', 'c1345000-0000-0000-0000-000000000003',
     'keep_later_member@example.com', 'Keep', 'Later', v_role_id, now(), 'active', '{}', '+1');

  INSERT INTO companies (id, email, phone, name)
  VALUES ('c1345000-0000-0000-0000-000000000005', 'keep-later@example.com', '+1-555-0013', 'Keep Later Test Company');

  INSERT INTO company_users (user_id, company_id, role_id)
  VALUES ('c1345000-0000-0000-0000-000000000004', 'c1345000-0000-0000-0000-000000000005', v_company_role_id);

  INSERT INTO your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
  VALUES
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Used Tuesday', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Never used', 100.0000, 'USD', '2026-03-01T00:00:00Z', NULL),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Boundary', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Price and use', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Empty upload', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Price only', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Pair Monday', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-02T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Pair Wednesday', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-04T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Upsert', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Put by id', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Both empty', 100.0000, 'USD', '2026-03-01T00:00:00Z', NULL),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Microsecond', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00.000000Z'),
    ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Admin fix', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-03T09:00:00Z');
END $$;

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{
  "sub": "c1345000-0000-0000-0000-000000000003",
  "app_metadata": { "internal_user_id": "c1345000-0000-0000-0000-000000000004" }
}', true);

-- ============================================================
-- Earlier, later and first use
-- ============================================================

UPDATE public.your_rates SET last_used_at = '2026-03-02T09:00:00Z' WHERE item_name = 'Used Tuesday';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Used Tuesday'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An update with an earlier time leaves the stored last_used_at unchanged'
);

UPDATE public.your_rates SET last_used_at = '2026-03-04T09:00:00Z' WHERE item_name = 'Used Tuesday';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Used Tuesday'),
  '2026-03-04T09:00:00Z'::timestamptz,
  'An update with a later time sets the new last_used_at'
);

UPDATE public.your_rates SET last_used_at = '2026-03-05T09:00:00Z' WHERE item_name = 'Never used';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Never used'),
  '2026-03-05T09:00:00Z'::timestamptz,
  'A first use sets last_used_at when none was stored'
);

-- ============================================================
-- Exact boundary: one second either side of the stored time
-- ============================================================

UPDATE public.your_rates SET last_used_at = '2026-03-03T08:59:59Z' WHERE item_name = 'Boundary';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Boundary'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'One second earlier than the stored time is refused'
);

UPDATE public.your_rates SET last_used_at = '2026-03-03T09:00:00Z' WHERE item_name = 'Boundary';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Boundary'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'The same time as the stored one leaves it unchanged'
);

UPDATE public.your_rates SET last_used_at = '2026-03-03T09:00:01Z' WHERE item_name = 'Boundary';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Boundary'),
  '2026-03-03T09:00:01Z'::timestamptz,
  'One second later than the stored time is accepted'
);

-- ============================================================
-- Other columns in the same update are still applied
-- ============================================================

UPDATE public.your_rates
SET rate_amount = 130.0000, entry_label = 'With operator', last_used_at = '2026-03-02T09:00:00Z'
WHERE item_name = 'Price and use';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Price and use'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An earlier time sent with a new price still leaves last_used_at unchanged'
);

SELECT is(
  (SELECT ROW(rate_amount, entry_label)::text FROM public.your_rates WHERE item_name = 'Price and use'),
  '(130.0000,"With operator")',
  'An earlier time sent with a new price and label still applies the price and label'
);

-- ============================================================
-- An empty time, and an update that leaves the column out
-- ============================================================

UPDATE public.your_rates SET last_used_at = NULL WHERE item_name = 'Empty upload';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Empty upload'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An empty time from a phone that has not seen the use does not erase the stored one'
);

UPDATE public.your_rates SET rate_amount = 140.0000 WHERE item_name = 'Price only';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Price only'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An update that leaves last_used_at out keeps it'
);

-- ============================================================
-- Two rows in one statement are each decided on their own
-- ============================================================

UPDATE public.your_rates
SET last_used_at = '2026-03-03T09:00:00Z'
WHERE item_name IN ('Pair Monday', 'Pair Wednesday');

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Pair Monday'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'In one statement, the row that held an earlier time takes the later one'
);

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Pair Wednesday'),
  '2026-03-04T09:00:00Z'::timestamptz,
  'In the same statement, the row that held a later time keeps it'
);

-- ============================================================
-- The upsert the phone sends lands on the existing row
-- ============================================================

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
VALUES ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Upsert', 150.0000, 'USD', '2026-03-06T00:00:00Z', '2026-03-02T09:00:00Z')
ON CONFLICT (company_id, category, item_name_key, equipment_method, entry_label_key)
DO UPDATE SET rate_amount = EXCLUDED.rate_amount, saved_at = EXCLUDED.saved_at, last_used_at = EXCLUDED.last_used_at;

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Upsert'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An upsert carrying an earlier time leaves the stored last_used_at unchanged'
);

SELECT is(
  (SELECT rate_amount FROM public.your_rates WHERE item_name = 'Upsert'),
  150.0000::numeric,
  'An upsert carrying an earlier time still applies the new price'
);

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
VALUES ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Upsert', 150.0000, 'USD', '2026-03-06T00:00:00Z', '2026-03-07T09:00:00Z')
ON CONFLICT (company_id, category, item_name_key, equipment_method, entry_label_key)
DO UPDATE SET rate_amount = EXCLUDED.rate_amount, saved_at = EXCLUDED.saved_at, last_used_at = EXCLUDED.last_used_at;

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Upsert'),
  '2026-03-07T09:00:00Z'::timestamptz,
  'An upsert carrying a later time sets the new last_used_at'
);

-- The phone's put is an upsert on id

INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
SELECT id, company_id, category, item_name, 160.0000, rate_currency, '2026-03-09T00:00:00Z', '2026-03-02T09:00:00Z'
FROM public.your_rates WHERE item_name = 'Put by id'
ON CONFLICT (id)
DO UPDATE SET rate_amount = EXCLUDED.rate_amount, saved_at = EXCLUDED.saved_at, last_used_at = EXCLUDED.last_used_at;

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Put by id'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An upsert on id carrying an earlier time leaves the stored last_used_at unchanged'
);

SELECT is(
  (SELECT rate_amount FROM public.your_rates WHERE item_name = 'Put by id'),
  160.0000::numeric,
  'An upsert on id carrying an earlier time still applies the new price'
);

SELECT is(
  (SELECT saved_at FROM public.your_rates WHERE item_name = 'Put by id'),
  '2026-03-09T00:00:00Z'::timestamptz,
  'An upsert on id carrying an earlier time still applies the new saved_at'
);

INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
SELECT id, company_id, category, item_name, 160.0000, rate_currency, saved_at, '2026-03-08T09:00:00Z'
FROM public.your_rates WHERE item_name = 'Put by id'
ON CONFLICT (id)
DO UPDATE SET rate_amount = EXCLUDED.rate_amount, last_used_at = EXCLUDED.last_used_at;

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Put by id'),
  '2026-03-08T09:00:00Z'::timestamptz,
  'An upsert on id carrying a later time sets the new last_used_at'
);

-- ============================================================
-- Empty on both sides, and a one microsecond difference
-- ============================================================

UPDATE public.your_rates SET last_used_at = NULL, rate_amount = 111.0000 WHERE item_name = 'Both empty';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Both empty'),
  NULL::timestamptz,
  'An empty time on a rate that was never used stays empty'
);

UPDATE public.your_rates SET last_used_at = '2026-03-03T08:59:59.999999Z' WHERE item_name = 'Microsecond';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Microsecond'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'A time one microsecond earlier than the stored one is refused'
);

-- ============================================================
-- A new row has nothing to compare with
-- ============================================================

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
VALUES ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Fresh insert', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-02T09:00:00Z');

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Fresh insert'),
  '2026-03-02T09:00:00Z'::timestamptz,
  'An insert keeps the time it was sent with'
);

-- ============================================================
-- A time far ahead of the server clock, and infinity
-- ============================================================

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
VALUES ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Future update', 100.0000, 'USD', '2026-03-01T00:00:00Z', '2026-03-02T09:00:00Z');

UPDATE public.your_rates SET last_used_at = now() + interval '2 days' WHERE item_name = 'Future update';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Future update'),
  now(),
  'An update with a time more than 1 day ahead stores the server time'
);

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
VALUES ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Future insert', 100.0000, 'USD', '2026-03-01T00:00:00Z', now() + interval '2 days');

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Future insert'),
  now(),
  'An insert with a time more than 1 day ahead stores the server time'
);

UPDATE public.your_rates SET last_used_at = now() + interval '12 hours' WHERE item_name = 'Future update';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Future update'),
  now() + interval '12 hours',
  'A time less than 1 day ahead is kept as sent'
);

SELECT throws_ok(
  $$UPDATE public.your_rates SET last_used_at = 'infinity' WHERE item_name = 'Future update'$$,
  '22023',
  'last_used_at must be a finite time',
  'An update with infinity is refused'
);

SELECT throws_ok(
  $$UPDATE public.your_rates SET last_used_at = '-infinity' WHERE item_name = 'Future update'$$,
  '22023',
  'last_used_at must be a finite time',
  'An update with -infinity is refused'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, last_used_at)
    VALUES ('c1345000-0000-0000-0000-000000000005', 'equipment', 'Infinity insert', 100.0000, 'USD', '2026-03-01T00:00:00Z', 'infinity')$$,
  '22023',
  'last_used_at must be a finite time',
  'An insert with infinity is refused'
);

-- ============================================================
-- The rule is not limited to the authenticated role
-- ============================================================

RESET ROLE;

UPDATE public.your_rates SET last_used_at = '2026-03-02T09:00:00Z' WHERE item_name = 'Admin fix';

SELECT is(
  (SELECT last_used_at FROM public.your_rates WHERE item_name = 'Admin fix'),
  '2026-03-03T09:00:00Z'::timestamptz,
  'An earlier time written by a role other than authenticated is also refused'
);

SELECT * FROM finish();
ROLLBACK;
