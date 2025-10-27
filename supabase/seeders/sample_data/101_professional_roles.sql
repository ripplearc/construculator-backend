-- Professional Roles Seeder
-- This file creates the foundational professional roles needed for the system

INSERT INTO "professional_roles" (
  "id",
  "name"
) VALUES
  (
    '550e8400-e29b-41d4-a716-446655440001',
    'Project Manager'
  ),
  (
    '550e8400-e29b-41d4-a716-446655440002',
    'Cost Estimator'
  ),
  (
    '550e8400-e29b-41d4-a716-446655440003',
    'Construction Manager'
  ),
  (
    '550e8400-e29b-41d4-a716-446655440004',
    'Architect'
  ),
  (
    '550e8400-e29b-41d4-a716-446655440005',
    'Engineer'
  )
ON CONFLICT ("id") DO NOTHING;
