BEGIN;

-- Tests for CA-963: user_consents, the append-only log of consent decisions.
-- Covers the action enum wire contract, the constraints that must NOT exist
-- (an FK to consent_versions, a uniqueness rule on re-acceptance), the
-- version >= 0 allowance that withdrawals depend on, and the RLS posture:
-- own rows only, keyed on the internal_user_id JWT claim rather than
-- auth.uid(), with no update or delete path for anyone.

SELECT plan(13);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_table('public', 'user_consents', 'user_consents table should exist');
SELECT has_pk('public', 'user_consents', 'user_consents should have a primary key');
SELECT col_is_fk('public', 'user_consents', 'user_id', 'user_consents.user_id is a FK to users');

SELECT is(
  (SELECT array_to_string(array_agg(e.enumlabel ORDER BY e.enumsortorder), ',') COLLATE "C"
     FROM pg_enum e
     JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = 'consent_action_enum'),
  'accepted,withdrawn' COLLATE "C",
  'consent_action_enum carries exactly the client wire values, in order'
);

SELECT has_index(
  'public', 'user_consents', 'user_consents_user_type_recorded_idx',
  'The (user_id, consent_type, recorded_at) lookup index exists'
);

-- ============================================================
-- Constraints that must NOT exist
--
-- Both would look like reasonable review additions, and both would break a
-- real path — so their absence is asserted rather than left to comments.
-- ============================================================

SELECT is(
  (SELECT count(*) FROM pg_constraint
     WHERE conrelid = 'public.user_consents'::regclass
       AND contype = 'f'
       AND confrelid = 'public.consent_versions'::regclass),
  0::bigint,
  'user_consents has NO foreign key to consent_versions (log survives corrections there)'
);

SELECT is(
  (SELECT count(*) FROM pg_constraint
     WHERE conrelid = 'public.user_consents'::regclass
       AND contype = 'u'),
  0::bigint,
  'user_consents has NO unique constraint (re-accepting after a withdrawal is legitimate)'
);

-- ============================================================
-- Fixtures
-- ============================================================

DO $$
DECLARE
  v_role_id uuid := '55555555-5555-5555-5555-555555555555';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Consent Test Role');

  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     'consent_owner@example.com', 'Consent', 'Owner', v_role_id, now(), 'active', '{}', '+1'),
    ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
     'consent_other@example.com', 'Consent', 'Other', v_role_id, now(), 'active', '{}', '+1');

  -- The other user's record: must never be visible to the owner below.
  INSERT INTO user_consents (user_id, consent_type, version, action)
  VALUES ('33333333-3333-3333-3333-333333333333', 'terms_and_privacy', 1, 'accepted');
END $$;

-- A full accept -> withdraw -> re-accept cycle on ONE version. This is the
-- sequence a UNIQUE (user_id, consent_type, version) would break, and the
-- withdrawal-with-nothing-on-file case is what version >= 0 exists for.
SELECT lives_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action) VALUES
      ('11111111-1111-1111-1111-111111111111', 'terms_and_privacy', 0, 'withdrawn'),
      ('11111111-1111-1111-1111-111111111111', 'terms_and_privacy', 2, 'accepted'),
      ('11111111-1111-1111-1111-111111111111', 'terms_and_privacy', 2, 'withdrawn'),
      ('11111111-1111-1111-1111-111111111111', 'terms_and_privacy', 2, 'accepted')$$,
  'A withdrawal at version 0 and a re-accept of the same version both insert cleanly'
);

SELECT throws_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action)
    VALUES ('11111111-1111-1111-1111-111111111111', 'analytics', -1, 'accepted')$$,
  '23514',
  NULL,
  'A negative version is still rejected'
);

-- ============================================================
-- RLS — own rows only, via the internal_user_id claim
-- ============================================================

SET LOCAL ROLE authenticated;

-- Note the claim shape: app_metadata.internal_user_id is users.id, NOT the
-- sub/credential_id. A policy written against auth.uid() would compare
-- credential_id to user_id and match nothing.
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222",
  "app_metadata": { "internal_user_id": "11111111-1111-1111-1111-111111111111" }
}', true);

SELECT is(
  (SELECT count(*) FROM public.user_consents),
  4::bigint,
  'A user sees their own consent records and only those'
);

SELECT throws_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action)
    VALUES ('33333333-3333-3333-3333-333333333333', 'analytics', 1, 'accepted')$$,
  '42501',
  NULL,
  'A user cannot record consent in someone else''s name'
);

-- UPDATE and DELETE raise nothing: with no policy the rows are invisible to
-- the statement, which succeeds having changed zero rows. Asserted on the
-- surviving data rather than with throws_ok, so a permissive policy added
-- later shows up as a mutated or missing row.
UPDATE public.user_consents SET action = 'accepted'
  WHERE user_id = '11111111-1111-1111-1111-111111111111' AND action = 'withdrawn';

SELECT is(
  (SELECT count(*) FROM public.user_consents
     WHERE user_id = '11111111-1111-1111-1111-111111111111' AND action = 'withdrawn'),
  2::bigint,
  'A user cannot rewrite their consent history (append-only)'
);

DELETE FROM public.user_consents WHERE user_id = '11111111-1111-1111-1111-111111111111';

SELECT is(
  (SELECT count(*) FROM public.user_consents
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  4::bigint,
  'A user cannot delete their consent history (append-only)'
);

SELECT * FROM finish();
ROLLBACK;
