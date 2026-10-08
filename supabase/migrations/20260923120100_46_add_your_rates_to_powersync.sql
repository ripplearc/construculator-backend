-- CA-1145: Add your_rates (and company_users) to the PowerSync publication.
--
-- The `user_rates` sync stream added to powersync/sync-config.yaml in this
-- change selects from your_rates, gated by a company_users membership CTE
-- that reimplements your_rates_select_policy's jwt_user_is_company_member()
-- check. PowerSync bypasses Postgres RLS and evaluates sync rules against
-- replicated state, so both tables need to be in the publication -- a table
-- missing from it produces a stream that connects, reports healthy, and
-- delivers nothing, the same failure mode migrations 41/43 would have had
-- without this step.
--
-- company_users is NOT itself exposed to clients -- no sync stream selects
-- from it directly; it exists only to evaluate the user_rates CTE, the same
-- role role_permissions/permissions play for user_cost_estimates
-- (20260520000000_add_cost_estimates_to_powersync.sql). It was not already
-- in the publication (checked via pg_publication_tables and by grepping
-- past migrations for it in an ALTER PUBLICATION context) before this.
--
-- Rollback (manual; Supabase migrations are append-only):
--   ALTER PUBLICATION powersync DROP TABLE
--     public.your_rates,
--     public.company_users;
--
-- After dropping, restart the PowerSync replicator so it stops streaming.
-- https://ripplearc.youtrack.cloud/issue/CA-1145

ALTER PUBLICATION powersync ADD TABLE
  public.your_rates,
  public.company_users;
