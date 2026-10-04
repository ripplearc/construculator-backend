begin;
select plan(9);

-- USERS table: critical columns
SELECT has_column('public', 'users', 'id', 'users.id column exists');
SELECT col_type_is('public', 'users', 'id', 'uuid', 'users.id is uuid');
SELECT col_not_null('public', 'users', 'email', 'users.email is NOT NULL');
SELECT has_column('public', 'users', 'created_at', 'users.created_at column exists');

-- PROJECTS table: critical columns
SELECT has_column('public', 'projects', 'id', 'projects.id column exists');
SELECT col_type_is('public', 'projects', 'id', 'uuid', 'projects.id is uuid');
SELECT has_column('public', 'projects', 'project_name', 'projects.project_name column exists');
SELECT col_not_null('public', 'projects', 'project_name', 'projects.project_name is NOT NULL');



-- Data insertion tests (with rollback)
DO $$
DECLARE
  user_id uuid := '11111111-1111-1111-1111-111111111111';
  credential_id uuid := '22222222-2222-2222-2222-222222222222';
  project_id uuid := '33333333-3333-3333-3333-333333333333';
  role_id uuid := '55555555-5555-5555-5555-555555555555';
BEGIN
  -- Insert a dummy professional_role
  INSERT INTO professional_roles (id, name) VALUES ('66666666-6666-6666-6666-666666666666', 'Test Role');
  -- CA-995: users.credential_id now FKs to auth.users(id), so a real auth
  -- account has to exist before it can be referenced here.
  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', credential_id, 'authenticated', 'authenticated',
    'testuser@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''
  );
  INSERT INTO users (
    id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code
  ) VALUES (
    user_id, credential_id, 'testuser@example.com', 'Test', 'User', '66666666-6666-6666-6666-666666666666', now(), 'active', '{}', '+1'
  );
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status) VALUES (project_id, 'Test Project', user_id, now(), now(), 'active');
END $$;
SELECT ok(true, 'Able to insert minimal user, project, and company_user');
select * from finish();
rollback;