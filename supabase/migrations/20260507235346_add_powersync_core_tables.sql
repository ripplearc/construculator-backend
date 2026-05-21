-- Add core tables to PowerSync publication
--
-- Rollback (manual; Supabase migrations are append-only):
--   ALTER PUBLICATION powersync DROP TABLE
--     public.users,
--     public.projects,
--     public.project_members;
--
-- After dropping, restart the PowerSync replicator so it stops streaming these tables.

ALTER PUBLICATION powersync ADD TABLE
  public.users,
  public.projects,
  public.project_members;
