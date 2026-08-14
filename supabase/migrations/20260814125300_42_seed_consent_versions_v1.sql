-- CA-963: Publish version 1 of each consent document.
--
-- A migration rather than a seeder: supabase/seeders/ only runs on local
-- `start` / `db reset`, so a seeded row would never reach production — and an
-- empty consent_versions leaves every gate check resolving to
-- ConsentIndeterminate, which blocks nothing but presents nothing either.
--
-- TODO: the document_url values below are PROVISIONAL. No published legal
-- document URL existed when this was written; these mirror the shape the
-- client's temporary in-memory source fakes. Confirm both against the real
-- published documents before CONSENT_GATE_ENABLED is switched on in
-- production. https://ripplearc.youtrack.cloud/issue/CA-963
--
-- ON CONFLICT DO NOTHING so a re-run against a database that already has v1
-- (a partially applied deploy, a re-seeded branch) is a no-op rather than a
-- unique violation that fails the whole migration.

INSERT INTO public.consent_versions
  (consent_type, version, document_url, effective_from, published_at)
VALUES
  ('terms_and_privacy', 1, 'https://ripplearc.com/legal/terms-and-privacy', now(), now()),
  ('analytics',         1, 'https://ripplearc.com/legal/analytics',         now(), now())
ON CONFLICT (consent_type, version) DO NOTHING;
