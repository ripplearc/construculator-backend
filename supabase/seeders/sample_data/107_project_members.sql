-- Project Members Seeder

INSERT INTO "project_members" (
  "project_id",
  "user_id",
  "role_id",
  "invited_by_user_id",
  "joined_at",
  "membership_status"
) VALUES
  (
    (SELECT "id" FROM "projects" WHERE "project_name" = 'Downtown Office Complex'),
    (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'),
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    NULL,
    now(),
    'joined'
  ),
  (
    (SELECT "id" FROM "projects" WHERE "project_name" = 'Residential Housing Development'),
    (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'),
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    NULL,
    now(),
    'joined'
  ),
  (
    (SELECT "id" FROM "projects" WHERE "project_name" = 'Shopping Mall Renovation'),
    (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'),
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    NULL,
    now(),
    'joined'
  ),
  (
    (SELECT "id" FROM "projects" WHERE "project_name" = 'Industrial Warehouse'),
    (SELECT "id" FROM "users" WHERE "email" = 'seeder@example.com'),
    (SELECT "id" FROM "roles" WHERE "role_name" = 'Admin'),
    NULL,
    now(),
    'joined'
  )
ON CONFLICT ("project_id", "user_id") DO NOTHING;
