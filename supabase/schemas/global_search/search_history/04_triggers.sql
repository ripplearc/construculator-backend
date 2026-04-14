-- Triggers for search_history.
-- Depends on functions defined in 03_functions.sql.

-- ============================================================
-- Atomically increment search_count on repeat-search upserts.
--
-- WHEN guard: fires only when the upsert conflict key columns
-- (user_id, search_term, scope) are all unchanged, scoping the
-- trigger strictly to the repeat-search upsert path.
-- ============================================================
CREATE OR REPLACE TRIGGER "trigger_increment_search_count"
  BEFORE UPDATE ON "public"."search_history"
  FOR EACH ROW
  WHEN (
    OLD.user_id IS NOT DISTINCT FROM NEW.user_id
    AND OLD.search_term IS NOT DISTINCT FROM NEW.search_term
    AND OLD.scope IS NOT DISTINCT FROM NEW.scope
  )
  EXECUTE FUNCTION public.increment_search_count();

-- ============================================================
-- Maintain updated_at on every row change.
-- ============================================================
CREATE OR REPLACE TRIGGER "trigger_set_search_history_updated_at"
  BEFORE UPDATE ON "public"."search_history"
  FOR EACH ROW
  EXECUTE FUNCTION public.set_search_history_updated_at();
