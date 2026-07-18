BEGIN;

-- CA-806: project_members SELECT RLS.
-- A user sees their own rows (even pending "invited" ones) plus all rows of
-- projects where they hold get_members; strangers see nothing.

SELECT plan(6);

-- =============================================================================
-- Fixture: one project, three users (member Admin/joined, invitee, stranger)
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'aaaa5555-5555-5555-5555-555555555555';
  v_admin_role_id uuid;
  v_viewer_role_id uuid;
  v_project_id uuid := 'aaaa3333-3333-3333-3333-333333333333';
  v_member_id uuid := 'aaaa1111-1111-1111-1111-111111111111';
  v_invitee_id uuid := 'aaaa2222-2222-2222-2222-222222222222';
  v_stranger_id uuid := 'aaaa4444-4444-4444-4444-444444444444';
BEGIN
  SELECT id INTO v_admin_role_id FROM roles WHERE role_name = 'Admin';
  SELECT id INTO v_viewer_role_id FROM roles WHERE role_name = 'Viewer';

  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'RLS Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code) VALUES
    (v_member_id, 'aaaa1111-0000-0000-0000-000000000001', 'pm_rls_member@example.com', 'Member', 'User', v_prof_role_id, 'active', '{}', '+1'),
    (v_invitee_id, 'aaaa2222-0000-0000-0000-000000000002', 'pm_rls_invitee@example.com', 'Invitee', 'User', v_prof_role_id, 'active', '{}', '+1'),
    (v_stranger_id, 'aaaa4444-0000-0000-0000-000000000004', 'pm_rls_stranger@example.com', 'Stranger', 'User', v_prof_role_id, 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id) VALUES (v_project_id, 'pm rls test project', v_member_id);

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_member_id, v_admin_role_id, 'joined', now());
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, invited_by_user_id)
    VALUES (v_project_id, v_invitee_id, v_viewer_role_id, 'invited', v_member_id);
END $$;

-- =============================================================================
-- 1. Joined member with get_members sees all rows of the project
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{
  "sub": "aaaa1111-0000-0000-0000-000000000001",
  "app_metadata": {
    "internal_user_id": "aaaa1111-1111-1111-1111-111111111111",
    "projects": {"aaaa3333-3333-3333-3333-333333333333": ["get_members", "view_project"]}
  }
}', true);

SELECT is(
  (SELECT count(*)::int FROM project_members WHERE project_id = 'aaaa3333-3333-3333-3333-333333333333'),
  2,
  'Member holding get_members sees both membership rows of the project'
);

-- =============================================================================
-- 2. Invited user (no project claims yet) sees only their own pending row
-- =============================================================================
SELECT set_config('request.jwt.claims', '{
  "sub": "aaaa2222-0000-0000-0000-000000000002",
  "app_metadata": {
    "internal_user_id": "aaaa2222-2222-2222-2222-222222222222",
    "projects": {}
  }
}', true);

SELECT is(
  (SELECT count(*)::int FROM project_members WHERE project_id = 'aaaa3333-3333-3333-3333-333333333333'),
  1,
  'Invited user sees exactly one row of the project'
);

SELECT is(
  (SELECT membership_status::text FROM project_members WHERE project_id = 'aaaa3333-3333-3333-3333-333333333333'),
  'invited',
  'The row the invited user sees is their own pending membership'
);

-- =============================================================================
-- 3. Authenticated stranger sees nothing
-- =============================================================================
SELECT set_config('request.jwt.claims', '{
  "sub": "aaaa4444-0000-0000-0000-000000000004",
  "app_metadata": {
    "internal_user_id": "aaaa4444-4444-4444-4444-444444444444",
    "projects": {}
  }
}', true);

SELECT is(
  (SELECT count(*)::int FROM project_members WHERE project_id = 'aaaa3333-3333-3333-3333-333333333333'),
  0,
  'Authenticated non-member sees no membership rows'
);

-- =============================================================================
-- 4. Missing internal_user_id claim (legacy token) exposes nothing
-- =============================================================================
SELECT set_config('request.jwt.claims', '{
  "sub": "aaaa4444-0000-0000-0000-000000000004",
  "app_metadata": {"projects": {}}
}', true);

SELECT is(
  (SELECT count(*)::int FROM project_members WHERE project_id = 'aaaa3333-3333-3333-3333-333333333333'),
  0,
  'Token without internal_user_id claim yields no rows (no error)'
);

-- =============================================================================
-- 5. RLS-driven policies elsewhere still work: user_has_project_permission is
--    SECURITY DEFINER, so the member can still read their project row.
-- =============================================================================
SELECT set_config('request.jwt.claims', '{
  "sub": "aaaa1111-0000-0000-0000-000000000001",
  "app_metadata": {
    "internal_user_id": "aaaa1111-1111-1111-1111-111111111111",
    "projects": {"aaaa3333-3333-3333-3333-333333333333": ["get_members", "view_project"]}
  }
}', true);

SELECT is(
  (SELECT count(*)::int FROM projects WHERE id = 'aaaa3333-3333-3333-3333-333333333333'),
  1,
  'projects SELECT policy (user_has_project_permission) still passes for a joined member'
);

RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
