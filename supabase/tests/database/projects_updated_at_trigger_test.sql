BEGIN;

-- CA-752: projects.updated_at must be auto-bumped on UPDATE.

SELECT plan(2);

DO $$
DECLARE
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_admin_role_id uuid := '66666666-6666-6666-6666-666666666666';
  v_project_id uuid := '33333333-3333-3333-3333-333333333333';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user_id, v_credential_id, 'updated_at_trigger@example.com', 'Trigger', 'Test', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_admin_role_id, 'TestAdmin', 4, 'project');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_admin_role_id, id FROM permissions WHERE permission_key IN ('view_project', 'edit_project');

  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (v_project_id, 'trigger test project', v_user_id, now() - interval '60 days', now() - interval '60 days', 'active');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_user_id, v_admin_role_id, 'joined', now());
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

UPDATE projects SET project_name = 'trigger test project (renamed)' WHERE id = '33333333-3333-3333-3333-333333333333';

SELECT cmp_ok(
  (SELECT updated_at FROM projects WHERE id = '33333333-3333-3333-3333-333333333333'),
  '>',
  now() - interval '1 minute',
  'projects.updated_at trigger bumps the timestamp on UPDATE'
);

SELECT isnt(
  (SELECT updated_at FROM projects WHERE id = '33333333-3333-3333-3333-333333333333'),
  (SELECT created_at FROM projects WHERE id = '33333333-3333-3333-3333-333333333333'),
  'updated_at no longer matches the original created_at after an edit'
);

RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
