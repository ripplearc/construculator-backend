-- RLS Policies for public and semi-public tables

-- professional_roles: Truly public (needed before signup for role selection)
CREATE POLICY "professional_roles_select_public" ON "professional_roles"
  FOR SELECT
  USING (true);

