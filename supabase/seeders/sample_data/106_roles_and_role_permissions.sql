-- Roles and Role Permissions Seeder
-- This file creates roles, assigns permissions to roles, and assigns users to roles for testing
-- Note: Permissions are defined in supabase/seeders/constants/permissions.sql

-- Insert roles with different permission levels
INSERT INTO "roles" (
  "id",
  "role_name",
  "level",
  "description",
  "context_type"
) VALUES
  (
    'a50e8400-e29b-41d4-a716-446655440001',
    'Admin',
    4,
    'Full control over project including all cost estimations and team management',
    'project'
  ),
  (
    'a50e8400-e29b-41d4-a716-446655440002',
    'Manager',
    3,
    'Can manage project, view and edit cost estimations, manage team members',
    'project'
  ),
  (
    'a50e8400-e29b-41d4-a716-446655440003',
    'Collaborator',
    2,
    'Can view and create cost estimations, limited team management',
    'project'
  ),
  (
    'a50e8400-e29b-41d4-a716-446655440004',
    'Viewer',
    2,
    'Read-only access to project and cost estimations',
    'project'
  )
ON CONFLICT ("id") DO NOTHING;

-- Assign permissions to Admin role (highest level)
INSERT INTO "role_permissions" (
  "role_id",
  "permission_id"
) VALUES
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'get_cost_estimations')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'add_cost_estimation')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'view_project')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'edit_project')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'delete_project')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'delete_cost_estimation')
  )
ON CONFLICT ("role_id", "permission_id") DO NOTHING;

-- Assign permissions to Manager role
INSERT INTO "role_permissions" (
  "role_id",
  "permission_id"
) VALUES
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Manager'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'get_cost_estimations')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Manager'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'add_cost_estimation')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Manager'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'view_project')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Manager'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'edit_project')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Manager'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'delete_cost_estimation')
  )
ON CONFLICT ("role_id", "permission_id") DO NOTHING;

-- Assign permissions to Collaborator role
INSERT INTO "role_permissions" (
  "role_id",
  "permission_id"
) VALUES
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Collaborator'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'get_cost_estimations')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Collaborator'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'add_cost_estimation')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Collaborator'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'view_project')
  )
ON CONFLICT ("role_id", "permission_id") DO NOTHING;

-- Assign permissions to Viewer role
INSERT INTO "role_permissions" (
  "role_id",
  "permission_id"
) VALUES
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Viewer'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'get_cost_estimations')
  ),
  (
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Viewer'),
    (SELECT "id" FROM "permissions" WHERE "permission_key" = 'view_project')
  )
ON CONFLICT ("role_id", "permission_id") DO NOTHING;