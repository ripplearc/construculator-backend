-- Project Tags RLS Policies

ALTER TABLE "public"."project_tags" ENABLE ROW LEVEL SECURITY;

-- SELECT Policy
-- Tag assignments follow project visibility: a project's tags are visible
-- only to users who can view the project itself (mirrors
-- projects_select_policy on the projects table).

DROP POLICY IF EXISTS "project_tags_select_policy" ON "public"."project_tags";
CREATE POLICY "project_tags_select_policy" ON "public"."project_tags"
  FOR SELECT
  USING (
    "user_has_project_permission"(
      "project_id",
      'view_project',
      "auth"."uid"()
    )
  );

-- No INSERT/UPDATE/DELETE policies defined.
-- Write access is intentionally restricted to service_role / migrations only,
-- matching the tags reference-data pattern.
