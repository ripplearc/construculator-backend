-- RLS policies for project_search_history
-- Four policies, all personal ownership: SELECT / INSERT / UPDATE / DELETE.
-- Project Search history is personal — there is no cross-user visibility.

ALTER TABLE "public"."project_search_history" ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Personal ownership.
-- user_id stores auth.uid() directly (= users.credential_id).
-- ============================================================
CREATE POLICY "project_search_history_select_policy" ON "public"."project_search_history"
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "project_search_history_insert_policy" ON "public"."project_search_history"
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "project_search_history_update_policy" ON "public"."project_search_history"
  FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "project_search_history_delete_policy" ON "public"."project_search_history"
  FOR DELETE
  USING (user_id = auth.uid());
