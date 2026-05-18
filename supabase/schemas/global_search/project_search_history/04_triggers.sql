-- Triggers for project_search_history.
-- Reuses trigger functions defined in
-- supabase/schemas/global_search/search_history/03_functions.sql:
--   * public.increment_search_count
--   * public.set_search_history_updated_at
-- Both are table-agnostic (they only touch NEW.search_count / NEW.updated_at)
-- and can be safely attached here without redefinition.

-- ============================================================
-- Atomically increment search_count on repeat-search upserts.
--
-- WHEN guard: fires only when the upsert conflict key columns
-- (user_id, search_term) are unchanged, scoping the trigger strictly
-- to the repeat-search upsert path.
--
-- BEFORE UPDATE means created_at is never touched on conflict, so the
-- original timestamp is preserved as required by the AC.
-- ============================================================
CREATE OR REPLACE TRIGGER "trigger_increment_project_search_count"
  BEFORE UPDATE ON "public"."project_search_history"
  FOR EACH ROW
  WHEN (
    OLD.user_id IS NOT DISTINCT FROM NEW.user_id
    AND OLD.search_term IS NOT DISTINCT FROM NEW.search_term
  )
  EXECUTE FUNCTION public.increment_search_count();

-- ============================================================
-- Maintain updated_at on every row change.
-- ============================================================
CREATE OR REPLACE TRIGGER "trigger_set_project_search_history_updated_at"
  BEFORE UPDATE ON "public"."project_search_history"
  FOR EACH ROW
  EXECUTE FUNCTION public.set_search_history_updated_at();
