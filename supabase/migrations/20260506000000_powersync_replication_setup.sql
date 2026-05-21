-- PowerSync Replication Setup Migration
-- This enables PostgreSQL logical replication for PowerSync.
--
-- PREREQUISITE: PostgreSQL must be running with `wal_level = logical`.
-- Supabase's local stack and managed instances already set this; on a custom
-- Postgres install, set it in postgresql.conf and restart before this migration runs.

-- Create publication for specific tables (demo: professional_roles only)
-- TODO: CA-647 Configure Sync Streams for core entities (users, projects, memberships, estimation)
-- NOTE: Do NOT edit this migration to add tables. Migrations are append-only —
-- create a new migration that runs `ALTER PUBLICATION powersync ADD TABLE ...`.
CREATE PUBLICATION powersync FOR TABLE public.professional_roles;
