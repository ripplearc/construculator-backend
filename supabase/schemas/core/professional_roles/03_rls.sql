-- Professional Roles RLS Policies

ALTER TABLE "public"."professional_roles" ENABLE ROW LEVEL SECURITY;


-- Public SELECT Policy
-- Anyone can view available professional roles

CREATE POLICY "professional_roles_select_public" ON "public"."professional_roles" FOR SELECT USING (true);

-- No INSERT/UPDATE/DELETE policies defined.
-- Write access is intentionally restricted to service_role / migrations only.
-- Reference data is managed via seed files (supabase/seeders/sample_data/101_professional_roles.sql),
-- not direct user writes.
