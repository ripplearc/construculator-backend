-- CA-971: Add the consent tables to the PowerSync publication.
--
-- The `consent_versions` and `user_consents` sync streams added to
-- powersync/sync-config.yaml in this change select from these two tables.
-- A sync stream query is evaluated against replicated state, so a table not
-- in the `powersync` publication produces a stream that connects, reports
-- healthy, and delivers nothing — the same failure mode migrations 41/43
-- would have had without this step. Membership in the publication is what
-- actually starts the logical replication.
--
-- Both tables keep the default replica identity (the primary key), matching
-- every other table in this publication. Neither needs REPLICA IDENTITY FULL:
-- `user_consents` has no UPDATE or DELETE path at all (no RLS policy for
-- either, which is what makes it append-only — see
-- schemas/consent/user_consents/03_rls.sql), and `consent_versions` is
-- written only by migration.
--
-- Rollback (manual; Supabase migrations are append-only):
--   ALTER PUBLICATION powersync DROP TABLE
--     public.consent_versions,
--     public.user_consents;
--
-- After dropping, restart the PowerSync replicator so it stops streaming.
-- https://ripplearc.youtrack.cloud/issue/CA-971

ALTER PUBLICATION powersync ADD TABLE
  public.consent_versions,
  public.user_consents;
