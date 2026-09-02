BEGIN;

-- Tests for CA-963: consent_versions and the current_consent_versions view.
-- Covers the enum wire contract with the Flutter client, the constraints that
-- keep an unusable requirement out of the table, the "which version is in
-- force" rules the view exists to own, the v1 seed, and the read-only-for-
-- clients RLS posture.

SELECT plan(18);

-- ============================================================
-- Shape
-- ============================================================

SELECT has_table('public', 'consent_versions', 'consent_versions table should exist');
SELECT has_pk('public', 'consent_versions', 'consent_versions should have a primary key');

-- Wire contract: these literals are compared against strings the Flutter
-- client sends (consent_wire_values.dart). Renaming a value here silently
-- stops matching on the client, so the exact set is pinned.
SELECT is(
  (SELECT array_to_string(array_agg(e.enumlabel ORDER BY e.enumsortorder), ',') COLLATE "C"
     FROM pg_enum e
     JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = 'consent_type_enum'),
  'terms_and_privacy,analytics' COLLATE "C",
  'consent_type_enum carries exactly the client wire values, in order'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'consent_versions_type_version_uq'
      AND conrelid = 'public.consent_versions'::regclass
      AND contype = 'u'
  ),
  'consent_versions has a UNIQUE constraint on (consent_type, version)'
);

-- ============================================================
-- Constraints — an unusable requirement must not reach the table
-- ============================================================

SELECT throws_ok(
  $$INSERT INTO public.consent_versions (consent_type, version, document_url)
    VALUES ('analytics', 0, 'https://example.com/doc')$$,
  '23514',
  NULL,
  'A version of 0 is rejected (versions are 1-based)'
);

-- A blank URL would present a consent page with nothing to read: the client
-- throws on it and resolves the throw to a status rather than an error, so the
-- failure would be invisible at runtime. Rejected on write instead.
SELECT throws_ok(
  $$INSERT INTO public.consent_versions (consent_type, version, document_url)
    VALUES ('analytics', 99, '   ')$$,
  '23514',
  NULL,
  'A blank document_url is rejected'
);

-- ============================================================
-- Seed
-- ============================================================

SELECT is(
  (SELECT count(*) FROM public.consent_versions WHERE version = 1),
  2::bigint,
  'The seed migration published version 1 of both consent types'
);

-- ============================================================
-- current_consent_versions — the rules the view exists to own
-- ============================================================

DO $$
BEGIN
  -- v2 is live, v3 is scheduled for next week. Seeded v1 is already present.
  INSERT INTO public.consent_versions (consent_type, version, document_url, effective_from)
  VALUES
    ('terms_and_privacy', 2, 'https://example.com/terms-v2', now() - interval '1 day'),
    ('terms_and_privacy', 3, 'https://example.com/terms-v3', now() + interval '7 days');
END $$;

SELECT is(
  (SELECT count(*) FROM public.current_consent_versions),
  2::bigint,
  'The view returns exactly one row per consent type'
);

SELECT is(
  (SELECT version FROM public.current_consent_versions
     WHERE consent_type = 'terms_and_privacy'),
  2,
  'The view returns the highest version whose effective_from has passed'
);

-- The whole point of effective_from: a version can be inserted ahead of time
-- without going live. If this fails, publishing v3 early re-gates every user.
SELECT is(
  (SELECT count(*) FROM public.current_consent_versions
     WHERE consent_type = 'terms_and_privacy' AND version = 3),
  0::bigint,
  'A version whose effective_from is still in the future is not yet in force'
);

-- The "nothing in force" branch. A consent type with no published row must
-- drop out of the view entirely rather than surface with a null version — the
-- client reads that absence as ConsentIndeterminate. The seed guarantees both
-- types always have a v1, so the branch is unreachable without retracting one;
-- the rows are parked and put back so the RLS assertions below still run
-- against the seeded state.
CREATE TEMP TABLE retracted_analytics ON COMMIT DROP AS
  SELECT * FROM public.consent_versions WHERE consent_type = 'analytics';

DELETE FROM public.consent_versions WHERE consent_type = 'analytics';

SELECT is(
  (SELECT count(*) FROM public.current_consent_versions
     WHERE consent_type = 'analytics'),
  0::bigint,
  'A consent type with nothing published is absent from the view, not null-filled'
);

SELECT is(
  (SELECT count(*) FROM public.current_consent_versions),
  1::bigint,
  'The other consent type still resolves while one has nothing in force'
);

INSERT INTO public.consent_versions SELECT * FROM retracted_analytics;

-- ============================================================
-- RLS — readable by any authenticated user, writable by none
-- ============================================================

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

SELECT ok(
  (SELECT count(*) FROM public.consent_versions) > 0,
  'An authenticated user can read published consent versions'
);

-- The client never selects the base table; it selects the view. These two
-- assertions cover that path from both sides. The behavioral one below reads
-- the view as authenticated, which fails if the base table's SELECT policy is
-- dropped (view returns zero rows) or the auto-exposed Data API grant is
-- revoked (permission denied). It cannot see security_invoker being flipped
-- off, because the SELECT policy is USING (true) — an owner-executed view and
-- a policy-governed one return the same rows here — so the declaration is
-- pinned separately in the catalog.
SELECT ok(
  (SELECT reloptions FROM pg_class WHERE relname = 'current_consent_versions')
    @> ARRAY['security_invoker=true'],
  'current_consent_versions is declared security_invoker (the caller''s policies govern it, not the owner''s)'
);

SELECT ok(
  (SELECT count(*) FROM public.current_consent_versions) > 0,
  'An authenticated user can read the resolver view through the SELECT policy and the Data API grant'
);

SELECT throws_ok(
  $$INSERT INTO public.consent_versions (consent_type, version, document_url)
    VALUES ('analytics', 42, 'https://example.com/self-published')$$,
  '42501',
  NULL,
  'An authenticated client cannot publish a consent version'
);

-- UPDATE and DELETE do NOT raise. With no policy for either command the rows
-- are simply invisible to the statement, so it succeeds having changed
-- nothing — which is why these assert on the surviving row rather than using
-- throws_ok. A regression that adds a permissive policy shows up as a changed
-- URL or a missing row.
UPDATE public.consent_versions
  SET document_url = 'https://tampered.example'
  WHERE consent_type = 'terms_and_privacy' AND version = 1;

SELECT is(
  (SELECT document_url FROM public.consent_versions
     WHERE consent_type = 'terms_and_privacy' AND version = 1),
  'https://ripplearc.com/legal/terms-and-privacy',
  'An authenticated client cannot rewrite a published consent version'
);

DELETE FROM public.consent_versions WHERE consent_type = 'analytics';

SELECT is(
  (SELECT count(*) FROM public.consent_versions WHERE consent_type = 'analytics'),
  1::bigint,
  'An authenticated client cannot retract a published consent version'
);

SELECT * FROM finish();
ROLLBACK;
