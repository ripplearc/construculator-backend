-- Projects Seeder
-- This file creates sample projects for testing and development

INSERT INTO "projects" ("id", "project_name", "description", "creator_user_id", "owning_company_id", "export_storage_provider") VALUES
  ('950e8400-e29b-41d4-a716-446655440001', 'Downtown Office Complex', 'Construction of a 15-story office building in downtown area', (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'), (SELECT "id" FROM "companies" WHERE "name" = 'BuildCorp Construction'), 'google_drive'),
  ('950e8400-e29b-41d4-a716-446655440002', 'Residential Housing Development', 'Construction of 50 single-family homes in suburban area', (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'), (SELECT "id" FROM "companies" WHERE "name" = 'BuildCorp Construction'), 'one_drive'),
  ('950e8400-e29b-41d4-a716-446655440003', 'Shopping Mall Renovation', 'Complete renovation of existing shopping mall including new stores and food court', (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'), NULL, 'dropbox'),
  ('950e8400-e29b-41d4-a716-446655440004', 'Industrial Warehouse', 'Construction of a 100,000 sq ft industrial warehouse facility', (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'), (SELECT "id" FROM "companies" WHERE "name" = 'Premium Builders Inc'), 'google_drive')
ON CONFLICT ("id") DO NOTHING;
