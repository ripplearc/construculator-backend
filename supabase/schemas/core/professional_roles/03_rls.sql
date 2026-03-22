-- Professional Roles RLS Policies

ALTER TABLE "public"."professional_roles" ENABLE ROW LEVEL SECURITY;


-- Public SELECT Policy
-- Anyone can view available professional roles

CREATE POLICY "professional_roles_select_public" ON "public"."professional_roles" FOR SELECT USING (true);
