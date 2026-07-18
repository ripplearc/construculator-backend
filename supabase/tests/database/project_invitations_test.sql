BEGIN;

-- CA-807 (1/4): project_invitations table shape, constraints, and RLS.

SELECT plan(10);

-- =============================================================================
-- 1. Table shape
-- =============================================================================
SELECT has_table('public', 'project_invitations', 'project_invitations table exists');
SELECT columns_are('public', 'project_invitations',
  ARRAY['id', 'project_id', 'email', 'role_id', 'invited_by_user_id', 'invited_at', 'status'],
  'project_invitations has the expected columns');
SELECT col_type_is('public', 'project_invitations', 'email', 'citext', 'email is citext');
SELECT col_not_null('public', 'project_invitations', 'invited_by_user_id', 'invited_by_user_id is NOT NULL');

SELECT has_enum('public', 'invitation_status_enum', 'invitation_status_enum exists');
SELECT enum_has_labels('public', 'invitation_status_enum',
  ARRAY['pending', 'accepted', 'declined', 'revoked'],
  'invitation_status_enum has the expected labels');

-- =============================================================================
-- 2. Fixture: inviter (Admin, joined) + one pending invitation
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'bbbb5555-5555-5555-5555-555555555555';
  v_admin_role_id uuid;
  v_project_id uuid := 'bbbb3333-3333-3333-3333-333333333333';
  v_inviter_id uuid := 'bbbb1111-1111-1111-1111-111111111111';
BEGIN
  SELECT id INTO v_admin_role_id FROM roles WHERE role_name = 'Admin';

  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Invitations Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code)
    VALUES (v_inviter_id, 'bbbb1111-0000-0000-0000-000000000001', 'pi_inviter@example.com', 'Inviter', 'User', v_prof_role_id, 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id) VALUES (v_project_id, 'invitations test project', v_inviter_id);
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_inviter_id, v_admin_role_id, 'joined', now());

  INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id)
    VALUES (v_project_id, 'Newcomer@Example.com', (SELECT id FROM roles WHERE role_name = 'Viewer'), v_inviter_id);
END $$;

-- =============================================================================
-- 3. citext + UNIQUE: same email in different case collides
-- =============================================================================
SELECT throws_ok(
  $$ INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id)
     VALUES ('bbbb3333-3333-3333-3333-333333333333', 'newcomer@example.COM',
             (SELECT id FROM roles WHERE role_name = 'Viewer'),
             'bbbb1111-1111-1111-1111-111111111111') $$,
  '23505',
  NULL,
  'UNIQUE (project_id, email) is case-insensitive via citext'
);

-- =============================================================================
-- 4. RLS: invite_member holders see rows; others see nothing; writes blocked
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{
  "sub": "bbbb1111-0000-0000-0000-000000000001",
  "app_metadata": {
    "internal_user_id": "bbbb1111-1111-1111-1111-111111111111",
    "projects": {"bbbb3333-3333-3333-3333-333333333333": ["invite_member", "get_members"]}
  }
}', true);

SELECT is(
  (SELECT count(*)::int FROM project_invitations WHERE project_id = 'bbbb3333-3333-3333-3333-333333333333'),
  1,
  'Member holding invite_member sees the pending invitation'
);

SELECT set_config('request.jwt.claims', '{
  "sub": "bbbb1111-0000-0000-0000-000000000001",
  "app_metadata": {
    "internal_user_id": "bbbb1111-1111-1111-1111-111111111111",
    "projects": {"bbbb3333-3333-3333-3333-333333333333": ["get_members"]}
  }
}', true);

SELECT is(
  (SELECT count(*)::int FROM project_invitations WHERE project_id = 'bbbb3333-3333-3333-3333-333333333333'),
  0,
  'Member without invite_member sees no invitations'
);

-- Uses the seeded Viewer role id directly: authenticated users cannot read the
-- roles table, and a subquery returning NULL would fail NOT NULL before RLS.
SELECT throws_ok(
  $$ INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id)
     VALUES ('bbbb3333-3333-3333-3333-333333333333', 'direct-write@example.com',
             'a50e8400-e29b-41d4-a716-446655440004',
             'bbbb1111-1111-1111-1111-111111111111') $$,
  '42501',
  NULL,
  'Direct INSERT into project_invitations is blocked for authenticated users'
);

RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
