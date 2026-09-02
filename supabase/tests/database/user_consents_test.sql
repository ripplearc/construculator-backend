BEGIN;

-- Tests for CA-963: user_consents, the append-only log of consent decisions.
-- Covers the action enum wire contract, the constraints that must NOT exist
-- (an FK to consent_versions, a uniqueness rule on re-acceptance), the
-- version >= 0 allowance that withdrawals depend on, the one-sided bound on
-- the client-supplied recorded_at, the users FK's refusal to cascade, and the
-- RLS posture: own rows only, keyed on the internal_user_id JWT claim rather
-- than auth.uid(), with no update or delete path for anyone and nothing at all
-- without the claim.

SELECT plan(20);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_table('public', 'user_consents', 'user_consents table should exist');
SELECT has_pk('public', 'user_consents', 'user_consents should have a primary key');
SELECT col_is_fk('public', 'user_consents', 'user_id', 'user_consents.user_id is a FK to users');

-- col_is_fk above says the FK exists; this says what it was declared to do on
-- delete. 'a' is NO ACTION; 'c' (CASCADE) would make this table lose the very
-- history it exists to keep. Metadata only -- the behavior itself is exercised
-- further down, once there is a user with consent rows to try deleting.
SELECT is(
  (SELECT confdeltype FROM pg_constraint
     WHERE conrelid = 'public.user_consents'::regclass
       AND contype = 'f'
       AND confrelid = 'public.users'::regclass),
  'a'::"char",
  'The users FK does NOT cascade on delete (consent history outlives the user row)'
);

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

-- recorded_at is supplied by the client on every insert and is the column
-- that orders this log, so it is bounded on the future side only. These two
-- pin the side that must stay open. Written against the second user so the
-- owner's row counts in the RLS block below stay what those assertions expect.
SELECT lives_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action, recorded_at)
    VALUES ('33333333-3333-3333-3333-333333333333', 'analytics', 1, 'accepted',
            now() - interval '400 days')$$,
  'A decision taken offline and synced long afterwards is still accepted'
);

SELECT lives_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action, recorded_at)
    VALUES ('33333333-3333-3333-3333-333333333333', 'analytics', 1, 'withdrawn',
            now() + interval '6 hours')$$,
  'A device clock running modestly fast is absorbed rather than rejected'
);

-- The behavioral half of the confdeltype assertion above. Catalog metadata
-- alone would still pass if someone later cleared this table from a BEFORE
-- DELETE trigger on users, leaving the FK untouched -- which is precisely the
-- drift the pin exists to catch. So try the delete, and require it to fail.
SELECT throws_ok(
  $$DELETE FROM public.users WHERE id = '33333333-3333-3333-3333-333333333333'$$,
  '23503',
  NULL,
  'Deleting a user who has consent rows is refused, not cascaded'
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

-- The INSERT policy checks only WHOSE row this is -- every field that decides
-- the gate is authored by the caller. Without the recorded_at bound a user
-- could future-date their own acceptance so that no later withdrawal ever
-- sorts above it, reporting consent-given indefinitely. Asserted here, under
-- the role that would actually do it, rather than only as a bare constraint.
SELECT throws_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action, recorded_at)
    VALUES ('11111111-1111-1111-1111-111111111111', 'terms_and_privacy', 99, 'accepted',
            timestamptz '2099-01-01')$$,
  '23514',
  NULL,
  'A user cannot future-date their own acceptance past the point of being superseded'
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

-- ============================================================
-- RLS — the claim missing entirely, not merely pointing elsewhere
--
-- custom_access_token_hook looks the id up by credential_id and can return
-- NULL when the users row does not exist yet (a first-login race), so an
-- authenticated caller with no internal_user_id claim is reachable. The
-- helper's NULLIF then yields NULL, and NULL never equals a NOT NULL
-- user_id -- the policies deny rather than leak. Asserted, not assumed.
-- ============================================================

SELECT set_config('request.jwt.claims',
  '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

SELECT is(
  (SELECT count(*) FROM public.user_consents),
  0::bigint,
  'A caller with no internal_user_id claim sees nothing, rather than everything'
);

SELECT throws_ok(
  $$INSERT INTO public.user_consents (user_id, consent_type, version, action)
    VALUES ('11111111-1111-1111-1111-111111111111', 'analytics', 1, 'accepted')$$,
  '42501',
  NULL,
  'A caller with no internal_user_id claim cannot record consent for anyone'
);

SELECT * FROM finish();
ROLLBACK;
