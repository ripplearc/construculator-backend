-- Base data seeder for cost estimates
-- This file creates the foundational data needed for cost estimates

-- Insert professional roles
INSERT INTO "professional_roles" ("id", "name") VALUES
  ('550e8400-e29b-41d4-a716-446655440001', 'Project Manager'),
  ('550e8400-e29b-41d4-a716-446655440002', 'Cost Estimator'),
  ('550e8400-e29b-41d4-a716-446655440003', 'Construction Manager'),
  ('550e8400-e29b-41d4-a716-446655440004', 'Architect'),
  ('550e8400-e29b-41d4-a716-446655440005', 'Engineer')
ON CONFLICT ("id") DO NOTHING;

-- Insert companies
INSERT INTO "companies" ("id", "email", "phone", "name", "logo_url") VALUES
  ('650e8400-e29b-41d4-a716-446655440001', 'contact@buildcorp.com', '+1-555-0101', 'BuildCorp Construction', 'https://example.com/logos/buildcorp.png'),
  ('650e8400-e29b-41d4-a716-446655440002', 'info@megac.com', '+1-555-0102', 'Mega Construction Ltd', 'https://example.com/logos/mega.png'),
  ('650e8400-e29b-41d4-a716-446655440003', 'hello@premb.com', '+1-555-0103', 'Premium Builders Inc', 'https://example.com/logos/premium.png')
ON CONFLICT ("id") DO NOTHING;

-- Insert a single user for seeder reference purposes
-- NOTE: This is for seeder data only - actual users should be created via Supabase API
INSERT INTO "users" ("id", "credential_id", "email", "phone", "first_name", "last_name", "professional_role", "user_preferences") VALUES
  ('750e8400-e29b-41d4-a716-446655440000', '850e8400-e29b-41d4-a716-446655440000', 'seeder@example.com', '+1-555-0000', 'Seeder', 'User', '550e8400-e29b-41d4-a716-446655440001', '{"theme": "light", "notifications": true}')
ON CONFLICT ("id") DO NOTHING;

-- Insert projects
INSERT INTO "projects" ("id", "project_name", "description", "creator_user_id", "owning_company_id", "export_storage_provider") VALUES
  ('950e8400-e29b-41d4-a716-446655440001', 'Downtown Office Complex', 'Construction of a 15-story office building in downtown area', '750e8400-e29b-41d4-a716-446655440000', '650e8400-e29b-41d4-a716-446655440001', 'google_drive'),
  ('950e8400-e29b-41d4-a716-446655440002', 'Residential Housing Development', 'Construction of 50 single-family homes in suburban area', '750e8400-e29b-41d4-a716-446655440000', '650e8400-e29b-41d4-a716-446655440001', 'one_drive'),
  ('950e8400-e29b-41d4-a716-446655440003', 'Shopping Mall Renovation', 'Complete renovation of existing shopping mall including new stores and food court', '750e8400-e29b-41d4-a716-446655440000', '650e8400-e29b-41d4-a716-446655440002', 'dropbox'),
  ('950e8400-e29b-41d4-a716-446655440004', 'Industrial Warehouse', 'Construction of a 100,000 sq ft industrial warehouse facility', '750e8400-e29b-41d4-a716-446655440000', '650e8400-e29b-41d4-a716-446655440003', 'google_drive')
ON CONFLICT ("id") DO NOTHING;
