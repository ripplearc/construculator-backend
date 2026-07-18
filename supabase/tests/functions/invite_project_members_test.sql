BEGIN;

-- CA-807 (2/4): invite_project_members RPC — permission check, level rule,
-- registered/unregistered branching, re-invite after decline, notifications.

SELECT plan(14);

-- Seeded role ids (106_roles_and_role_permissions.sql)
-- Admin a50e8400-e29b-41d4-a716-446655440001 (4) / Manager ...02 (3)
-- Collaborator ...03 (2) / Viewer ...04 (1)

-- =============================================================================
-- Fixture
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'cccc5555-5555-5555-5555-555555555555';
  v_project_id uuid := 'cccc3333-3333-3333-3333-333333333333';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Invite RPC Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code) VALUES
    ('cccc1111-1111-1111-1111-111111111111', 'cccc1111-0000-0000-0000-000000000001', 'inv_admin@example.com', 'Admin', 'Caller', v_prof_role_id, 'active', '{}', '+1'),
    ('cccc1111-1111-1111-1111-222222222222', 'cccc1111-0000-0000-0000-000000000002', 'inv_collab@example.com', 'Collab', 'Caller', v_prof_role_id, 'active', '{}', '+1'),
    ('cccc1111-1111-1111-1111-333333333333', 'cccc1111-0000-0000-0000-000000000003', 'inv_viewer@example.com', 'Viewer', 'Caller', v_prof_role_id, 'active', '{}', '+1'),
    ('cccc1111-1111-1111-1111-444444444444', 'cccc1111-0000-0000-0000-000000000004', 'inv_target@example.com', 'Target', 'User', v_prof_role_id, 'active', '{}', '+1'),
    ('cccc1111-1111-1111-1111-555555555555', 'cccc1111-0000-0000-0000-000000000005', 'inv_declined@example.com', 'Declined', 'User', v_prof_role_id, 'active', '{}', '+1'),
    ('cccc1111-1111-1111-1111-666666666666', 'cccc1111-0000-0000-0000-000000000006', 'inv_outsider@example.com', 'Outsider', 'User', v_prof_role_id, 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id)
    VALUES (v_project_id, 'invite rpc test project', 'cccc1111-1111-1111-1111-111111111111');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at) VALUES
    (v_project_id, 'cccc1111-1111-1111-1111-111111111111', 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now()),
    (v_project_id, 'cccc1111-1111-1111-1111-222222222222', 'a50e8400-e29b-41d4-a716-446655440003', 'joined', now()),
    (v_project_id, 'cccc1111-1111-1111-1111-333333333333', 'a50e8400-e29b-41d4-a716-446655440004', 'joined', now());
  INSERT INTO project_members (project_id, user_id, role_id, membership_status)
    VALUES (v_project_id, 'cccc1111-1111-1111-1111-555555555555', 'a50e8400-e29b-41d4-a716-446655440004', 'declined');
END $$;

SET LOCAL ROLE authenticated;

-- =============================================================================
-- 1. Viewer (no invite_member) is rejected
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000003"}', true);
SELECT throws_ok(
  $$ SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
       '[{"email": "someone@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440004"}]') $$,
  '42501', NULL,
  'Viewer without invite_member cannot invite'
);

-- =============================================================================
-- 2. Level rule: Collaborator (2) cannot grant Admin (4)
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000002"}', true);
SELECT throws_ok(
  $$ SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
       '[{"email": "someone@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440001"}]') $$,
  '42501', NULL,
  'Collaborator cannot grant a role above their own level'
);

-- =============================================================================
-- 3-5. Admin invites a registered user
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000001"}', true);
SELECT is(
  (SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
     '[{"email": "inv_target@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440003"}]')
   -> 0 ->> 'result'),
  'invited',
  'Registered user invite returns outcome "invited"'
);

RESET ROLE;
SELECT is(
  (SELECT membership_status::text FROM project_members
   WHERE project_id = 'cccc3333-3333-3333-3333-333333333333'
     AND user_id = 'cccc1111-1111-1111-1111-444444444444'),
  'invited',
  'Registered invitee got a pending project_members row'
);
SELECT is(
  (SELECT count(*)::int FROM notifications
   WHERE recipient_user_id = 'cccc1111-1111-1111-1111-444444444444'
     AND related_project_id = 'cccc3333-3333-3333-3333-333333333333'
     AND notification_type = 'project_invite'),
  1,
  'Registered invitee received a project_invite notification'
);

-- =============================================================================
-- 6. Inviting the same user again reports already_member
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000001"}', true);
SELECT is(
  (SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
     '[{"email": "inv_target@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440003"}]')
   -> 0 ->> 'result'),
  'already_member',
  'Re-inviting an already-invited user reports already_member'
);

-- =============================================================================
-- 7-8. Unregistered email becomes a pending project_invitations row
-- =============================================================================
SELECT is(
  (SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
     '[{"email": "nobody-yet@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440004"}]')
   -> 0 ->> 'result'),
  'pending_signup',
  'Unregistered email invite returns outcome "pending_signup"'
);

RESET ROLE;
SELECT is(
  (SELECT status::text FROM project_invitations
   WHERE project_id = 'cccc3333-3333-3333-3333-333333333333'
     AND email = 'Nobody-Yet@example.com'),
  'pending',
  'Unregistered email got a pending project_invitations row (case-insensitive)'
);

-- =============================================================================
-- 9-10. A declined membership is re-invited in place
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000001"}', true);
SELECT is(
  (SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
     '[{"email": "inv_declined@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440004"}]')
   -> 0 ->> 'result'),
  'invited',
  'A declined member can be re-invited'
);

RESET ROLE;
SELECT results_eq(
  $$ SELECT membership_status::text, joined_at FROM project_members
     WHERE project_id = 'cccc3333-3333-3333-3333-333333333333'
       AND user_id = 'cccc1111-1111-1111-1111-555555555555' $$,
  $$ VALUES ('invited', NULL::timestamptz) $$,
  'Re-invited membership is back to invited with joined_at cleared'
);

-- =============================================================================
-- 11-12. Malformed input
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000001"}', true);
SELECT throws_ok(
  $$ SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
       '[{"email": "someone@example.com", "role_id": "00000000-0000-0000-0000-00000000dead"}]') $$,
  '22023', NULL,
  'Unknown role id aborts the batch'
);
SELECT throws_ok(
  $$ SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333', '[]') $$,
  '22023', NULL,
  'Empty invite array is rejected'
);

-- =============================================================================
-- 13. A registered non-member cannot invite
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "cccc1111-0000-0000-0000-000000000006"}', true);
SELECT throws_ok(
  $$ SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333',
       '[{"email": "someone@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440004"}]') $$,
  '42501', NULL,
  'A non-member of the project cannot invite'
);

-- =============================================================================
-- 14. anon has no EXECUTE on the RPC
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT invite_project_members('cccc3333-3333-3333-3333-333333333333', '[]') $$,
  '42501', NULL,
  'anon cannot execute invite_project_members'
);
RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
