-- Companies Seeder
-- This file creates sample companies for testing and development

-- Insert companies
INSERT INTO "companies" ("id", "email", "phone", "name", "logo_url") VALUES
  ('650e8400-e29b-41d4-a716-446655440001', 'contact@buildcorp.com', '+1-555-0101', 'BuildCorp Construction', 'https://placehold.co/400'),
  ('650e8400-e29b-41d4-a716-446655440002', 'info@megac.com', '+1-555-0102', 'Mega Construction Ltd', 'https://placehold.co/400'),
  ('650e8400-e29b-41d4-a716-446655440003', 'hello@premb.com', '+1-555-0103', 'Premium Builders Inc', 'https://placehold.co/400')
ON CONFLICT ("id") DO NOTHING;
