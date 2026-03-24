-- Trigger function to auto-increment search_count on search_history updates.
-- On an upsert conflict, Postgres fires a BEFORE UPDATE on the existing row.
-- This trigger intercepts that update and increments the count atomically.
CREATE OR REPLACE FUNCTION increment_search_count()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  NEW.search_count := OLD.search_count + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- WHEN guard: only fire when the upsert conflict key columns are unchanged
-- (user_id, search_term, scope). This scopes the trigger strictly to the
-- repeat-search upsert path and prevents accidental increments if any other
-- UPDATE touches the row (e.g. a direct UPDATE to has_results or project_id).
CREATE TRIGGER "trigger_increment_search_count"
  BEFORE UPDATE ON "search_history"
  FOR EACH ROW
  WHEN (
    OLD.user_id IS NOT DISTINCT FROM NEW.user_id
    AND OLD.search_term IS NOT DISTINCT FROM NEW.search_term
    AND OLD.scope IS NOT DISTINCT FROM NEW.scope
  )
  EXECUTE FUNCTION increment_search_count();

-- ============================================================
-- Auto-update updated_at on every row change.
-- ============================================================
CREATE OR REPLACE FUNCTION set_search_history_updated_at()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "trigger_set_search_history_updated_at"
  BEFORE UPDATE ON "search_history"
  FOR EACH ROW
  EXECUTE FUNCTION set_search_history_updated_at();

-- ============================================================
-- ROLLBACK
-- DROP TRIGGER IF EXISTS "trigger_increment_search_count" ON "search_history";
-- DROP FUNCTION IF EXISTS increment_search_count();
-- DROP TRIGGER IF EXISTS "trigger_set_search_history_updated_at" ON "search_history";
-- DROP FUNCTION IF EXISTS set_search_history_updated_at();
-- ============================================================
