-- Add cost_estimates (and permission lookup tables) to PowerSync publication
--
-- The `user_cost_estimates` sync stream in powersync/sync-config.yaml mirrors
-- the RLS policy from 20260313081637_migrate_cost_estimates_rls_to_jwt.sql
-- (gated by the 'get_cost_estimations' permission). PowerSync replicates
-- around Postgres RLS, so the sync rule MUST enforce the same permission
-- check the API enforces.
--
-- The sync rule joins role_permissions and permissions inside a CTE to find
-- which projects grant the user 'get_cost_estimations'. PowerSync evaluates
-- sync rules against replicated state, so those tables also need to be in
-- the publication. They are NOT exposed to clients — no sync stream selects
-- from them; they exist only to evaluate the cost_estimates CTE.
--
-- Rollback (manual; Supabase migrations are append-only):
--   ALTER PUBLICATION powersync DROP TABLE
--     public.cost_estimates,
--     public.role_permissions,
--     public.permissions;
--
-- After dropping, restart the PowerSync replicator so it stops streaming.

ALTER PUBLICATION powersync ADD TABLE
  public.cost_estimates,
  public.role_permissions,
  public.permissions;
