BEGIN;

-- CA-806: member-management permission keys must exist and be mapped to roles
-- exactly per the CA-784 matrix, and role levels must form a strict hierarchy.

SELECT plan(13);

-- =============================================================================
-- 1. Permission keys exist
-- =============================================================================
SELECT is(
  (SELECT count(*)::int FROM permissions
   WHERE permission_key IN
     ('get_members', 'invite_member', 'update_member_role', 'remove_member', 'get_task_assignments')),
  5,
  'All five member-management permission keys are seeded'
);

-- =============================================================================
-- 2. Role levels: strict hierarchy Admin 4 > Manager 3 > Collaborator 2 > Viewer 1
-- =============================================================================
SELECT is((SELECT level FROM roles WHERE role_name = 'Admin'), 4, 'Admin is level 4');
SELECT is((SELECT level FROM roles WHERE role_name = 'Manager'), 3, 'Manager is level 3');
SELECT is((SELECT level FROM roles WHERE role_name = 'Collaborator'), 2, 'Collaborator is level 2');
SELECT is((SELECT level FROM roles WHERE role_name = 'Viewer'), 1, 'Viewer is level 1 (CA-806 fix)');
SELECT is(
  (SELECT count(DISTINCT level)::int FROM roles
   WHERE role_name IN ('Admin', 'Manager', 'Collaborator', 'Viewer')),
  4,
  'The four canonical role levels are all distinct'
);

-- =============================================================================
-- 3. Matrix mappings: each key grants exactly the intended roles
-- =============================================================================
CREATE TEMP VIEW member_permission_grants AS
SELECT p.permission_key, r.role_name
FROM role_permissions rp
JOIN roles r ON r.id = rp.role_id
JOIN permissions p ON p.id = rp.permission_id
WHERE p.permission_key IN
  ('get_members', 'invite_member', 'update_member_role', 'remove_member', 'get_task_assignments');

SELECT bag_eq(
  $$ SELECT role_name FROM member_permission_grants WHERE permission_key = 'get_members' $$,
  ARRAY['Viewer', 'Collaborator', 'Manager', 'Admin'],
  'get_members: all four roles'
);

SELECT bag_eq(
  $$ SELECT role_name FROM member_permission_grants WHERE permission_key = 'invite_member' $$,
  ARRAY['Collaborator', 'Manager', 'Admin'],
  'invite_member: Collaborator and above'
);

SELECT bag_eq(
  $$ SELECT role_name FROM member_permission_grants WHERE permission_key = 'update_member_role' $$,
  ARRAY['Manager', 'Admin'],
  'update_member_role: Manager and above'
);

SELECT bag_eq(
  $$ SELECT role_name FROM member_permission_grants WHERE permission_key = 'remove_member' $$,
  ARRAY['Manager', 'Admin'],
  'remove_member: Manager and above'
);

SELECT bag_eq(
  $$ SELECT role_name FROM member_permission_grants WHERE permission_key = 'get_task_assignments' $$,
  ARRAY['Collaborator', 'Manager', 'Admin'],
  'get_task_assignments: Collaborator and above'
);

-- =============================================================================
-- 4. Helper functions introduced/hardened by CA-806
-- =============================================================================
SELECT has_function('public', 'jwt_internal_user_id', ARRAY[]::text[],
  'jwt_internal_user_id function exists');

SELECT is(
  (SELECT prosecdef FROM pg_proc
   WHERE proname = 'user_has_project_permission'
     AND pronamespace = 'public'::regnamespace),
  true,
  'user_has_project_permission is SECURITY DEFINER'
);

SELECT * FROM finish();

ROLLBACK;
