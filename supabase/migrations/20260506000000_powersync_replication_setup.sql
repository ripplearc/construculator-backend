-- PowerSync Replication Setup Migration
-- This enables PostgreSQL logical replication for PowerSync

-- ============================================================================
-- REPLICATION SLOT
-- ============================================================================
-- Create a logical replication slot for PowerSync to consume WAL events
-- The slot persists the replication position so PowerSync can resume after restarts

DO $$
BEGIN
  -- Check if the replication slot already exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_replication_slots WHERE slot_name = 'powersync_slot'
  ) THEN
    -- Create the slot using pgoutput plugin (standard Postgres logical replication)
    PERFORM pg_create_logical_replication_slot('powersync_slot', 'pgoutput');
    RAISE NOTICE 'Created replication slot: powersync_slot';
  ELSE
    RAISE NOTICE 'Replication slot powersync_slot already exists, skipping';
  END IF;
END $$;

-- ============================================================================
-- PUBLICATION
-- ============================================================================
-- Create a publication that defines which tables are replicated to PowerSync
-- Option 1 (current): Replicate ALL tables in the public schema
-- Option 2 (commented): Replicate specific tables only

DO $$
BEGIN
  -- Check if the publication already exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'powersync_publication'
  ) THEN
    -- Create publication for all tables
    -- This means any new tables are automatically included in replication
    CREATE PUBLICATION powersync_publication FOR ALL TABLES;
    RAISE NOTICE 'Created publication: powersync_publication (all tables)';
  ELSE
    RAISE NOTICE 'Publication powersync_publication already exists, skipping';
  END IF;
END $$;

-- ============================================================================
-- ALTERNATIVE: SPECIFIC TABLES ONLY
-- ============================================================================
-- Uncomment this block (and comment out the "FOR ALL TABLES" block above)
-- if you want fine-grained control over which tables are replicated

/*
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'powersync_publication'
  ) THEN
    CREATE PUBLICATION powersync_publication FOR TABLE
      users,
      companies,
      projects,
      project_members,
      cost_estimates,
      cost_items,
      cost_estimate_logs;
    RAISE NOTICE 'Created publication: powersync_publication (specific tables)';
  ELSE
    RAISE NOTICE 'Publication powersync_publication already exists, skipping';
  END IF;
END $$;
*/

-- ============================================================================
-- VERIFICATION (for manual inspection)
-- ============================================================================
-- These queries are commented out because migrations shouldn't SELECT
-- Run them manually if you need to verify the setup

-- Verify replication slot:
-- SELECT slot_name, plugin, slot_type, database, active
-- FROM pg_replication_slots
-- WHERE slot_name = 'powersync_slot';

-- Verify publication:
-- SELECT pubname, puballtables
-- FROM pg_publication
-- WHERE pubname = 'powersync_publication';

-- List tables in publication:
-- SELECT schemaname, tablename
-- FROM pg_publication_tables
-- WHERE pubname = 'powersync_publication'
-- ORDER BY schemaname, tablename;
