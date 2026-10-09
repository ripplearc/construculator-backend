BEGIN;

-- Tests for CA-1076: user_calculator_stores, the calculator's trade stores
-- that follow the user's account. Covers the shape (columns, the store-kind
-- enum's wire values, the two CHECKs, the partial index, the one-live-row-
-- per-seed unique index), the updated_at trigger the conflict rule rests on,
-- the users FK cascading on account deletion, the publication membership the
-- sync stream depends on, and the RLS posture: own rows only on every verb,
-- keyed on the internal_user_id JWT claim rather than auth.uid(), nothing at
-- all without the claim, and nothing for anon. The updated_at stamp and the
-- soft delete run as authenticated, the path the app takes.

SELECT plan(37);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_table('public', 'user_calculator_stores', 'user_calculator_stores table should exist');
SELECT has_pk('public', 'user_calculator_stores', 'user_calculator_stores should have a primary key');
SELECT col_is_fk('public', 'user_calculator_stores', 'user_id', 'user_calculator_stores.user_id is a FK to users');
SELECT col_type_is('public', 'user_calculator_stores', 'store_kind', 'calculator_store_kind_enum', 'store_kind is the store-kind enum');
SELECT col_type_is('public', 'user_calculator_stores', 'values', 'jsonb', 'values is jsonb');
SELECT col_not_null('public', 'user_calculator_stores', 'unit_system', 'unit_system is NOT NULL');
SELECT col_is_null('public', 'user_calculator_stores', 'deleted_at', 'deleted_at is nullable (soft delete)');
SELECT col_has_default('public', 'user_calculator_stores', 'updated_at', 'updated_at has a default');

SELECT is(
  (SELECT array_to_string(array_agg(e.enumlabel ORDER BY e.enumsortorder), ',') COLLATE "C"
     FROM pg_enum e
     JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = 'calculator_store_kind_enum'),
  'sheet_size,masonry_piece,footing_section,on_centre_spacing,fence_config,rate,waste,density' COLLATE "C",
  'calculator_store_kind_enum carries exactly the eight stores of term 2.16, in order'
);

SELECT has_index(
  'public', 'user_calculator_stores', 'user_calculator_stores_user_kind_idx',
  'The (user_id, store_kind) partial index exists'
);

SELECT has_index(
  'public', 'user_calculator_stores', 'user_calculator_stores_live_seed_key',
  'The one-live-row-per-seed unique index exists'
);

-- The users FK cascades ('c'): a trade store is the user's own preference,
-- so deleting the account takes its rows with it, as company_users does.
-- The behaviour itself is exercised at the end.
SELECT is(
  (SELECT confdeltype FROM pg_constraint
     WHERE conrelid = 'public.user_calculator_stores'::regclass
       AND contype = 'f'
       AND confrelid = 'public.users'::regclass),
  'c'::"char",
  'The users FK cascades on delete'
);

-- ============================================================
-- Publication: the sync stream reads replicated state, so a table outside
-- the publication connects and delivers nothing.
-- ============================================================

SELECT ok(
  EXISTS (SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'powersync'
              AND schemaname = 'public'
              AND tablename = 'user_calculator_stores'),
  'user_calculator_stores is in the powersync publication'
);

-- ============================================================
-- Fixtures
-- ============================================================

DO $$
DECLARE
  v_role_id uuid := '55555555-5555-5555-5555-555555555555';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Stores Test Role');
  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
     'stores_owner@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated',
     'stores_other@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
     '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', '');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     'stores_owner@example.com', 'Stores', 'Owner', v_role_id, now(), 'active', '{}', '+1'),
    ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
     'stores_other@example.com', 'Stores', 'Other', v_role_id, now(), 'active', '{}', '+1');

  -- The owner's rows: a user-added sheet size and a changed seed rate.
  INSERT INTO user_calculator_stores (id, user_id, store_kind, "values", unit_system) VALUES
    ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
     'sheet_size', '{"width_ticks": 3072, "height_ticks": 6912}', 'imperial'),
    ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
     'rate', '{"seed": "ft2", "rate": 13.5, "waste_percent": 5}', 'imperial');
  -- The other user's row: must never be visible to the owner below.
  INSERT INTO user_calculator_stores (user_id, store_kind, "values", unit_system) VALUES
    ('33333333-3333-3333-3333-333333333333', 'density', '{"name": "gravel", "pounds_per_cubic_yard": 3100}', 'metric');
END $$;

-- ============================================================
-- Constraints
-- ============================================================

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'density', '[1, 2]', 'imperial')$$,
  '23514',
  NULL,
  'values must be a JSON object, not a list'
);

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'density', '{"name": "sand"}', 'cubits')$$,
  '23514',
  NULL,
  'unit_system is imperial or metric and nothing else'
);

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'paint', '{}', 'imperial')$$,
  '22P02',
  NULL,
  'A store kind outside the enum is rejected'
);

-- ============================================================
-- One live row per changed seed
-- ============================================================

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'rate', '{"seed": "ft2", "rate": 14}', 'imperial')$$,
  '23505',
  NULL,
  'A second live row for the same seed, store and unit system is refused'
);

SELECT lives_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'rate', '{"seed": "ft2", "rate": 14}', 'metric')$$,
  'The same seed under the other unit system is a different row'
);

SELECT lives_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system) VALUES
    ('11111111-1111-1111-1111-111111111111', 'rate', '{"rate": 14}', 'imperial'),
    ('11111111-1111-1111-1111-111111111111', 'rate', '{"rate": 15}', 'imperial')$$,
  'Rows without a seed key are not restricted'
);

DELETE FROM public.user_calculator_stores
 WHERE user_id = '11111111-1111-1111-1111-111111111111'
   AND id NOT IN ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

-- ============================================================
-- RLS — own rows only, via the internal_user_id claim
-- ============================================================

SET LOCAL ROLE authenticated;

-- app_metadata.internal_user_id is users.id, NOT the sub/credential_id. A
-- policy written against auth.uid() would compare credential_id to user_id
-- and match nothing.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": { "internal_user_id": "11111111-1111-1111-1111-111111111111" }
}', true);

SELECT is(
  (SELECT count(*) FROM public.user_calculator_stores),
  2::bigint,
  'A user sees their own store rows and only those'
);

-- The conflict rule (last upload to arrive wins) rests on the server
-- stamping updated_at on every UPDATE. Run as the app does: through the
-- UPDATE policy, not as the table owner.
UPDATE public.user_calculator_stores
   SET updated_at = now() - interval '1 day'
 WHERE id = 'a0000000-0000-0000-0000-000000000001';

SELECT ok(
  (SELECT updated_at >= now() - interval '1 minute'
     FROM public.user_calculator_stores
    WHERE id = 'a0000000-0000-0000-0000-000000000001'),
  'updated_at is stamped by the server on UPDATE, whatever the client wrote'
);

-- Soft delete is an UPDATE through the same policy: the row stays.
UPDATE public.user_calculator_stores
   SET deleted_at = now()
 WHERE id = 'a0000000-0000-0000-0000-000000000002';

SELECT isnt_empty(
  $$SELECT 1 FROM public.user_calculator_stores
     WHERE id = 'a0000000-0000-0000-0000-000000000002' AND deleted_at IS NOT NULL$$,
  'A soft-deleted row stays in the table with deleted_at set'
);

-- A soft-deleted row frees its seed key for a new live row.
SELECT lives_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'rate', '{"seed": "ft2", "rate": 16}', 'imperial')$$,
  'A soft-deleted seed row no longer blocks a new live row for that seed'
);

DELETE FROM public.user_calculator_stores
 WHERE "values"->>'rate' = '16';

SELECT lives_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'on_centre_spacing', '{"ticks": 1280}', 'imperial')$$,
  'A user can add a row of their own'
);

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('33333333-3333-3333-3333-333333333333', 'on_centre_spacing', '{"ticks": 1280}', 'imperial')$$,
  '42501',
  NULL,
  'A user cannot write a row in someone else''s name'
);

-- An UPDATE that would hand the row to another user fails WITH CHECK.
SELECT throws_ok(
  $$UPDATE public.user_calculator_stores
       SET user_id = '33333333-3333-3333-3333-333333333333'
     WHERE id = 'a0000000-0000-0000-0000-000000000001'$$,
  '42501',
  NULL,
  'A user cannot hand their row to someone else'
);

-- An UPDATE of another user's row changes nothing: with no visible row the
-- statement reports success having touched zero rows, so the pin is that
-- the row survives unchanged.
UPDATE public.user_calculator_stores
   SET "values" = '{"name": "stolen"}'
 WHERE user_id = '33333333-3333-3333-3333-333333333333';

SELECT lives_ok(
  $$UPDATE public.user_calculator_stores
       SET "values" = '{"width_ticks": 3072, "height_ticks": 7680}'
     WHERE id = 'a0000000-0000-0000-0000-000000000001'$$,
  'A user can change their own row'
);

SELECT is(
  (SELECT "values"->>'width_ticks' FROM public.user_calculator_stores
     WHERE id = 'a0000000-0000-0000-0000-000000000001'),
  '3072',
  'The change landed on the owner''s row'
);

DELETE FROM public.user_calculator_stores
 WHERE user_id = '33333333-3333-3333-3333-333333333333';

SELECT lives_ok(
  $$DELETE FROM public.user_calculator_stores
     WHERE id = 'a0000000-0000-0000-0000-000000000002'$$,
  'A user can hard-delete their own row'
);

SELECT is(
  (SELECT count(*) FROM public.user_calculator_stores),
  2::bigint,
  'Two rows remain for the owner: the sheet size and the spacing just added'
);

-- Without the claim nothing is visible and nothing can be written.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222"
}', true);

SELECT is(
  (SELECT count(*) FROM public.user_calculator_stores),
  0::bigint,
  'Without the internal_user_id claim a user sees no rows'
);

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'waste', '{"percent": 10}', 'imperial')$$,
  '42501',
  NULL,
  'Without the claim a user cannot write a row, even their own'
);

-- anon has no policy at all.
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);

SELECT is(
  (SELECT count(*) FROM public.user_calculator_stores),
  0::bigint,
  'anon sees no rows'
);

SELECT throws_ok(
  $$INSERT INTO public.user_calculator_stores (user_id, store_kind, "values", unit_system)
    VALUES ('11111111-1111-1111-1111-111111111111', 'waste', '{"percent": 10}', 'imperial')$$,
  '42501',
  NULL,
  'anon cannot insert a row'
);

RESET ROLE;

-- The other user's row was never touched by the owner's UPDATE or DELETE.
SELECT is(
  (SELECT "values"->>'name' FROM public.user_calculator_stores
     WHERE user_id = '33333333-3333-3333-3333-333333333333'),
  'gravel',
  'Another user''s row is untouched by the owner''s writes'
);

-- The behavioural half of the confdeltype assertion: deleting the account
-- (auth.users cascades to users, which cascades here) removes the rows.
SELECT lives_ok(
  $$DELETE FROM auth.users WHERE id = '44444444-4444-4444-4444-444444444444'$$,
  'Deleting a user who has store rows succeeds'
);

SELECT is_empty(
  $$SELECT 1 FROM public.user_calculator_stores
     WHERE user_id = '33333333-3333-3333-3333-333333333333'$$,
  'The deleted user''s store rows went with the account'
);

SELECT * FROM finish();
ROLLBACK;
