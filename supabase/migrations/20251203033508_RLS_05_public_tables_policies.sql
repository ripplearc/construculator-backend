-- RLS Policies for public and semi-public tables

-- professional_roles: Truly public (needed before signup for role selection)
CREATE POLICY "professional_roles_select_public" ON "professional_roles"
  FOR SELECT
  USING (true);

-- =============================================================================
-- users: Public rows, but column-restricted for anonymous users
-- - Anonymous users: can only see id, email, first_name, last_name, profile_photo_url
-- - Authenticated users: full access to all columns
-- =============================================================================
CREATE POLICY "users_select_policy" ON "users"
  FOR SELECT
  USING (true);

-- Restrict anonymous users to safe columns only
REVOKE ALL ON "users" FROM anon;
GRANT SELECT (id, email, first_name, last_name, profile_photo_url, professional_role) ON "users" TO anon;

-- Authenticated users get full read access
GRANT SELECT ON "users" TO authenticated;
