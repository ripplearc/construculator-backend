begin;
select plan(12);

-- 1. Table existence
SELECT has_table('public', 'users', 'users table should exist');
SELECT has_table('public', 'projects', 'projects table should exist');
SELECT has_table('public', 'teams', 'teams table should exist');
SELECT has_table('public', 'company_users', 'company_users table should exist');

-- 2. Primary key presence
SELECT has_pk('public', 'users', 'users table should have a primary key');
SELECT has_pk('public', 'projects', 'projects table should have a primary key');

-- 3. Critical foreign keys
SELECT col_is_fk('public', 'company_users', 'user_id', 'company_users.user_id is a FK');
SELECT col_is_fk('public', 'company_users', 'company_id', 'company_users.company_id is a FK');
SELECT col_is_fk('public', 'project_members', 'project_id', 'project_members.project_id is a FK');
SELECT col_is_fk('public', 'project_members', 'user_id', 'project_members.user_id is a FK');

-- 4. Essential unique constraint (compound)
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'teams'
      AND indexname = 'company_team_name_uq'
  ),
  'teams should have unique index company_team_name_uq on (company_id, team_name)'
);

-- 5. Critical compound index
SELECT has_index('public', 'project_members','project_user_membership_uq', ARRAY['project_id', 'user_id'], 'project_user_membership_uq should exist');

select * from finish();
rollback;