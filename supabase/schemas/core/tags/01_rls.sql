-- Tags RLS Policies

-- RLS is already enabled for "tags" (see 20250514131510_enable_rls.sql).

-- Public SELECT Policy
-- Tags are reference data used for search filtering; anyone can read them.

CREATE POLICY "tags_select_public" ON "public"."tags" FOR SELECT USING (true);

-- No INSERT/UPDATE/DELETE policies defined.
-- Write access is intentionally restricted to service_role / migrations only,
-- matching the professional_roles reference-data pattern.
