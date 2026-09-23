BEGIN;

-- Tests for CA-1145: the replication side of the user_rates sync stream.
--
-- powersync/sync-config.yaml is a YAML file no database test can read, so
-- the two things it depends on are pinned here instead: that both
-- your_rates and company_users are actually replicated (a stream selecting
-- a table outside the publication connects, reports healthy, and delivers
-- nothing -- there is no error to notice), and that every column the
-- stream's query and accessible_companies CTE name still exists.

SELECT plan(16);

-- ============================================================
-- Publication membership
-- ============================================================

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'powersync'
      AND schemaname = 'public'
      AND tablename = 'your_rates'
  ),
  'your_rates is replicated by the powersync publication'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'powersync'
      AND schemaname = 'public'
      AND tablename = 'company_users'
  ),
  'company_users is replicated by the powersync publication (needed to evaluate the user_rates stream''s accessible_companies CTE, not synced to any client directly)'
);

-- ============================================================
-- Columns the user_rates stream SELECTs from your_rates
-- ============================================================

SELECT has_column('public', 'your_rates', 'id',
  'your_rates.id is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'company_id',
  'your_rates.company_id is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'category',
  'your_rates.category is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'item_name',
  'your_rates.item_name is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'rate_amount',
  'your_rates.rate_amount is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'rate_currency',
  'your_rates.rate_currency is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'unit',
  'your_rates.unit is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'equipment_method',
  'your_rates.equipment_method is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'entry_label',
  'your_rates.entry_label is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'saved_at',
  'your_rates.saved_at is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'created_at',
  'your_rates.created_at is selected by the user_rates stream');
SELECT has_column('public', 'your_rates', 'updated_at',
  'your_rates.updated_at is selected by the user_rates stream');

-- ============================================================
-- Columns the user_rates stream's accessible_companies CTE reads from
-- company_users
-- ============================================================

SELECT has_column('public', 'company_users', 'user_id',
  'company_users.user_id is read by the user_rates stream''s accessible_companies CTE');
SELECT has_column('public', 'company_users', 'company_id',
  'company_users.company_id is read by the user_rates stream''s accessible_companies CTE');

SELECT * FROM finish();
ROLLBACK;
