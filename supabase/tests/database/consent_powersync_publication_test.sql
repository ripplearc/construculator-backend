BEGIN;

-- Tests for CA-971: the replication side of the consent sync streams.
--
-- powersync/sync-config.yaml is a YAML file no database test can read, so the
-- two things it depends on are pinned here instead: that both consent tables
-- are actually replicated, and that every column its SELECTs name still
-- exists. A stream selecting a table outside the publication connects,
-- reports healthy, and delivers nothing — there is no error to notice — so
-- membership is pinned rather than assumed.

SELECT plan(16);

-- ============================================================
-- Publication membership
-- ============================================================

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'powersync'
      AND schemaname = 'public'
      AND tablename = 'consent_versions'
  ),
  'consent_versions is replicated by the powersync publication'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'powersync'
      AND schemaname = 'public'
      AND tablename = 'user_consents'
  ),
  'user_consents is replicated by the powersync publication'
);

-- ============================================================
-- Columns the consent_versions stream SELECTs
--
-- The client's schema.dart declares the same list; PowerSync silently drops
-- a column present on one side and not the other, so a rename here has to
-- fail loudly somewhere.
-- ============================================================

SELECT has_column('public', 'consent_versions', 'id',
  'consent_versions.id is selected by the consent_versions stream');
SELECT has_column('public', 'consent_versions', 'consent_type',
  'consent_versions.consent_type is selected by the consent_versions stream');
SELECT has_column('public', 'consent_versions', 'version',
  'consent_versions.version is selected by the consent_versions stream');
SELECT has_column('public', 'consent_versions', 'document_url',
  'consent_versions.document_url is selected by the consent_versions stream');
-- effective_from is selected even though no DTO field holds it: the stream
-- syncs the full publication history rather than the current_consent_versions
-- view (a view has no replication identity, and the view's own
-- `effective_from <= now()` predicate is fired by no row change), so the
-- client needs this column to resolve which version is in force.
SELECT has_column('public', 'consent_versions', 'effective_from',
  'consent_versions.effective_from is selected by the consent_versions stream');
SELECT has_column('public', 'consent_versions', 'published_at',
  'consent_versions.published_at is selected by the consent_versions stream');

-- ============================================================
-- Columns the user_consents stream SELECTs
-- ============================================================

SELECT has_column('public', 'user_consents', 'id',
  'user_consents.id is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'user_id',
  'user_consents.user_id is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'consent_type',
  'user_consents.consent_type is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'version',
  'user_consents.version is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'action',
  'user_consents.action is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'recorded_at',
  'user_consents.recorded_at is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'app_version',
  'user_consents.app_version is selected by the user_consents stream');
SELECT has_column('public', 'user_consents', 'platform',
  'user_consents.platform is selected by the user_consents stream');

SELECT * FROM finish();
ROLLBACK;
