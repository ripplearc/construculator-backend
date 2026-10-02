BEGIN;

-- Tests for CA-1145: your_rates, the contractor's personal saved-rate book.
-- Covers table/PK/FK shape, the UNIQUE NULLS NOT DISTINCT constraint that
-- enforces the (company_id, category, item_name, entry_label) collision rule
-- from Decision 55 -- including the both-NULL-label case a plain UNIQUE
-- constraint would miss -- RLS scoping across two companies via
-- jwt_user_is_company_member(), the no-claim denial-by-default case, and the
-- shared updated_at trigger.

SELECT plan(26);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_table('public', 'your_rates', 'your_rates table should exist');
SELECT has_pk('public', 'your_rates', 'your_rates should have a primary key');
SELECT col_is_fk('public', 'your_rates', 'company_id', 'your_rates.company_id is a FK to companies');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'your_rates_company_category_item_label_key'
      AND conrelid = 'public.your_rates'::regclass
      AND contype = 'u'
  ),
  'your_rates has a UNIQUE constraint on (company_id, category, item_name, entry_label)'
);

SELECT is(
  (SELECT indnullsnotdistinct FROM pg_index
     WHERE indexrelid = 'public.your_rates_company_category_item_label_key'::regclass),
  true,
  'The collision constraint treats NULLs as equal (NULLS NOT DISTINCT), catching the both-NULL-label case'
);

SELECT is(
  (SELECT array_to_string(array_agg(e.enumlabel ORDER BY e.enumsortorder), ',') COLLATE "C"
     FROM pg_enum e
     JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = 'equipment_pricing_method_enum'),
  'day,job' COLLATE "C",
  'equipment_pricing_method_enum carries exactly the Flutter EquipmentPricingMethod.name wire values, in order'
);

-- No DELETE policy: append-only-by-omission, matching user_consents.
SELECT is(
  (SELECT count(*) FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'your_rates' AND cmd = 'DELETE'),
  0::bigint,
  'your_rates has NO DELETE policy (deleting a saved rate is out of scope for CA-1145)'
);

-- ============================================================
-- Fixtures: two companies, one member each, plus the roles/users plumbing
-- company_users and users FKs require.
-- ============================================================

DO $$
DECLARE
  v_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_company_role_id uuid := '66666666-6666-6666-6666-666666666666';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Your Rates Test Role');
  INSERT INTO roles (id, role_name, level, context_type)
    VALUES (v_company_role_id, 'Your Rates Test Company Role', 1, 'project');

  -- CA-995: users.credential_id now FKs to auth.users(id).
  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
     'rates_owner@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated',
     'rates_other@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     'rates_owner@example.com', 'Rates', 'Owner', v_role_id, now(), 'active', '{}', '+1'),
    ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
     'rates_other@example.com', 'Rates', 'Other', v_role_id, now(), 'active', '{}', '+1');

  -- Company A (owner is a member) and Company B (the other user is a member).
  INSERT INTO companies (id, email, phone, name)
  VALUES
    ('77777777-7777-7777-7777-777777777777', 'rates-company-a@example.com', '+1-555-0001', 'Your Rates Test Company A'),
    ('88888888-8888-8888-8888-888888888888', 'rates-company-b@example.com', '+1-555-0002', 'Your Rates Test Company B');

  INSERT INTO company_users (user_id, company_id, role_id)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777', v_company_role_id),
    ('33333333-3333-3333-3333-333333333333', '88888888-8888-8888-8888-888888888888', v_company_role_id);

  -- Company B's rate: must never be visible to, or writable by, Company A's member.
  INSERT INTO your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
  VALUES ('88888888-8888-8888-8888-888888888888', 'material', 'Rebar #4', 12.5000, 'USD', now());
END $$;

-- ============================================================
-- Collision constraint (Decision 55), exercised as postgres (bypasses RLS,
-- isolates the constraint layer from the policy layer below).
-- ============================================================

-- created_at/updated_at are backdated on this one row (rather than left at
-- their now() default) so the trigger test below has something to detect:
-- now() is frozen for the whole duration of this transaction, so a
-- default-vs-post-trigger comparison against now() would trivially match
-- even if the trigger never ran.
SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, created_at, updated_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Excavator', 250.0000, 'USD', now(), now() - interval '60 days', now() - interval '60 days')$$,
  'A first save into a fresh (company_id, category, item_name) grouping, with no entry_label, succeeds'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Excavator', 275.0000, 'USD', now())$$,
  '23505',
  NULL,
  'A second unlabeled save into the same grouping is rejected (both entry_label NULL collide via NULLS NOT DISTINCT)'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, entry_label)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Excavator', 300.0000, 'USD', now(), 'Rental Co A')$$,
  'A save into the same grouping with a distinct, non-NULL entry_label succeeds as a new row'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, entry_label)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Excavator', 320.0000, 'USD', now(), 'Rental Co B')$$,
  'A second, differently-labeled save into the same grouping also succeeds -- both entries are retrievable'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, entry_label)
    VALUES ('77777777-7777-7777-7777-777777777777', 'equipment', 'Excavator', 999.0000, 'USD', now(), 'Rental Co A')$$,
  '23505',
  NULL,
  'Re-saving with a label that already exists in the grouping collides (this is the "update in place" case an app-level upsert targets)'
);

SELECT is(
  (SELECT count(*) FROM public.your_rates
     WHERE company_id = '77777777-7777-7777-7777-777777777777'
       AND category = 'equipment' AND item_name = 'Excavator'),
  3::bigint,
  'Exactly the three surviving rows exist for the Excavator grouping (unlabeled, Rental Co A, Rental Co B)'
);

-- A different item_name, or a different category, is a different grouping
-- entirely -- confirms the index is not over-broad.
SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'material', 'Excavator', 10.0000, 'USD', now())$$,
  'The same item_name under a different category is a different grouping and does not collide'
);

-- ============================================================
-- updated_at trigger
-- ============================================================

SELECT lives_ok(
  $$UPDATE public.your_rates SET rate_amount = 111.0000
    WHERE company_id = '77777777-7777-7777-7777-777777777777'
      AND category = 'equipment' AND item_name = 'Excavator' AND entry_label IS NULL$$,
  'Updating a your_rates row succeeds'
);

SELECT cmp_ok(
  (SELECT updated_at FROM public.your_rates
     WHERE company_id = '77777777-7777-7777-7777-777777777777'
       AND category = 'equipment' AND item_name = 'Excavator' AND entry_label IS NULL),
  '>',
  now() - interval '1 minute',
  'your_rates.updated_at trigger bumps the timestamp on UPDATE'
);

SELECT isnt(
  (SELECT updated_at FROM public.your_rates
     WHERE company_id = '77777777-7777-7777-7777-777777777777'
       AND category = 'equipment' AND item_name = 'Excavator' AND entry_label IS NULL),
  (SELECT created_at FROM public.your_rates
     WHERE company_id = '77777777-7777-7777-7777-777777777777'
       AND category = 'equipment' AND item_name = 'Excavator' AND entry_label IS NULL),
  'updated_at no longer matches the backdated created_at after the UPDATE (trigger fired)'
);

-- ============================================================
-- RLS -- company membership, via jwt_user_is_company_member()
-- ============================================================

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": { "internal_user_id": "11111111-1111-1111-1111-111111111111" }
}', true);

SELECT is(
  (SELECT count(*) FROM public.your_rates),
  4::bigint,
  'Company A''s member sees only Company A''s four rows, never Company B''s'
);

SELECT is(
  (SELECT count(*) FROM public.your_rates WHERE company_id = '88888888-8888-8888-8888-888888888888'),
  0::bigint,
  'Company A''s member sees zero rows scoped to Company B, even when filtering for them explicitly'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'labor', 'Framing crew', 45.0000, 'USD', now())$$,
  'A company member can save a rate for their own company'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('88888888-8888-8888-8888-888888888888', 'labor', 'Framing crew', 45.0000, 'USD', now())$$,
  '42501',
  NULL,
  'A user cannot insert a rate into a company they do not belong to'
);

-- An ordinary in-place update (no company_id change) on the member's own
-- row succeeds, so the retarget test below is isolated to the WITH CHECK
-- clause and not just USING denying the row outright.
SELECT lives_ok(
  $$UPDATE public.your_rates SET rate_amount = 46.0000
    WHERE company_id = '77777777-7777-7777-7777-777777777777'
      AND category = 'labor' AND item_name = 'Framing crew'$$,
  'A company member can update one of their own rows without changing company_id'
);

SELECT throws_ok(
  $$UPDATE public.your_rates SET company_id = '88888888-8888-8888-8888-888888888888'
    WHERE company_id = '77777777-7777-7777-7777-777777777777'
      AND category = 'labor' AND item_name = 'Framing crew'$$,
  '42501',
  NULL,
  'A company member cannot retarget their own row to a company they do not belong to (WITH CHECK)'
);

-- Checked as postgres (RLS bypassed): Company A's member has no SELECT
-- visibility into Company B's rows at all, so re-running this count under
-- their own session would read 0 whether or not the retarget above had
-- (wrongly) succeeded -- it would prove nothing about the write path.
RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.your_rates WHERE company_id = '88888888-8888-8888-8888-888888888888'),
  1::bigint,
  'Company B''s row count is unchanged by every write attempt above'
);

SET LOCAL ROLE authenticated;

-- ============================================================
-- RLS -- the claim missing entirely
-- ============================================================

SELECT set_config('request.jwt.claims',
  '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

SELECT is(
  (SELECT count(*) FROM public.your_rates),
  0::bigint,
  'A caller with no internal_user_id claim sees nothing, rather than everything'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
    VALUES ('77777777-7777-7777-7777-777777777777', 'material', 'Plywood', 30.0000, 'USD', now())$$,
  '42501',
  NULL,
  'A caller with no internal_user_id claim cannot save a rate for any company'
);

SELECT * FROM finish();
ROLLBACK;
