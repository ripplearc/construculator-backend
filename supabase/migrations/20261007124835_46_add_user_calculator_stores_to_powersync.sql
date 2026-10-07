-- CA-1076: Add user_calculator_stores to the PowerSync publication.
--
-- The `user_calculator_stores` sync stream added to powersync/sync-config.yaml
-- in this change selects from this table. A sync stream query is evaluated
-- against replicated state, so a table not in the `powersync` publication
-- produces a stream that connects, reports healthy, and delivers nothing
-- (see migration 44_add_consent_tables_to_powersync.sql). Membership in the
-- publication is what actually starts the logical replication.
--
-- Default replica identity (the primary key), matching every other table in
-- this publication. Updates and soft deletes carry the primary key, which is
-- all the replicator needs to apply them.
--
-- Rollback (manual; Supabase migrations are append-only):
--   ALTER PUBLICATION powersync DROP TABLE public.user_calculator_stores;
--
-- After dropping, restart the PowerSync replicator so it stops streaming.
-- https://ripplearc.youtrack.cloud/issue/CA-1076

ALTER PUBLICATION powersync ADD TABLE
  public.user_calculator_stores;
