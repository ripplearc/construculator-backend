-- RLS policies for search_history
-- Five policies: four for personal CRUD ownership, one for teammate visibility.

ALTER TABLE "public"."search_history" ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Personal ownership: users can fully manage their own rows.
-- user_id stores auth.uid() directly (= users.credential_id).
-- ============================================================
CREATE POLICY "search_history_select_policy" ON "public"."search_history"
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "search_history_insert_policy" ON "public"."search_history"
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "search_history_update_policy" ON "public"."search_history"
  FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "search_history_delete_policy" ON "public"."search_history"
  FOR DELETE
  USING (user_id = auth.uid());

-- ============================================================
-- Teammate visibility: allow reading search_history rows that
-- belong to a shared project. Required for the teammate history
-- fallback in get_search_suggestions() with SECURITY INVOKER.
-- ============================================================
CREATE POLICY "search_history_teammate_select_policy" ON "public"."search_history"
  FOR SELECT
  USING (
    project_id IN (
      SELECT pm.project_id
      FROM project_members pm
      JOIN users u ON pm.user_id = u.id
      WHERE u.credential_id = auth.uid()
        AND pm.membership_status = 'joined'
    )
  );
