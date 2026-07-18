BEGIN;

-- CA-807 (4/4): signup conversion — pending project_invitations for a newly
-- registered email convert into invited memberships + notifications, exactly
-- once, case-insensitively, and only for that email.

SELECT plan(8);

-- =============================================================================
-- Fixture: two projects, each with a pending invitation for the same email
-- (different case), plus a pending invitation for an unrelated email and a
-- declined invitation that must NOT convert.
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'abab5555-5555-5555-5555-555555555555';
  v_inviter_id uuid := 'abab1111-1111-1111-1111-111111111111';
  v_project_a uuid := 'abab3333-3333-3333-3333-333333333331';
  v_project_b uuid := 'abab3333-3333-3333-3333-333333333332';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Conversion Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code)
    VALUES (v_inviter_id, 'abab1111-0000-0000-0000-000000000001', 'conv_inviter@example.com', 'Conv', 'Inviter', v_prof_role_id, 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id) VALUES
    (v_project_a, 'conversion test project A', v_inviter_id),
    (v_project_b, 'conversion test project B', v_inviter_id);

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at) VALUES
    (v_project_a, v_inviter_id, 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now()),
    (v_project_b, v_inviter_id, 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now());

  INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id, status) VALUES
    (v_project_a, 'Newbie@Example.com', 'a50e8400-e29b-41d4-a716-446655440003', v_inviter_id, 'pending'),
    (v_project_b, 'newbie@example.com', 'a50e8400-e29b-41d4-a716-446655440004', v_inviter_id, 'pending'),
    (v_project_a, 'someone-else@example.com', 'a50e8400-e29b-41d4-a716-446655440004', v_inviter_id, 'pending');
  INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id, status)
    VALUES (v_project_b, 'was-declined@example.com', 'a50e8400-e29b-41d4-a716-446655440004', v_inviter_id, 'declined');
END $$;

-- =============================================================================
-- 1-5. Signup converts both pending invitations for the email, with the
--      invited role preserved and notifications written
-- =============================================================================
DO $$
BEGIN
  -- Simulates the profile-row creation step of signup.
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code)
    VALUES ('abab2222-2222-2222-2222-222222222222', 'abab2222-0000-0000-0000-000000000002', 'newbie@EXAMPLE.com', 'New', 'Bie', 'abab5555-5555-5555-5555-555555555555', 'active', '{}', '+1');
END $$;

SELECT is(
  (SELECT count(*)::int FROM project_members
   WHERE user_id = 'abab2222-2222-2222-2222-222222222222' AND membership_status = 'invited'),
  2,
  'Both pending invitations converted into invited memberships'
);

SELECT is(
  (SELECT role_id FROM project_members
   WHERE user_id = 'abab2222-2222-2222-2222-222222222222'
     AND project_id = 'abab3333-3333-3333-3333-333333333331'),
  'a50e8400-e29b-41d4-a716-446655440003'::uuid,
  'Converted membership preserves the invited role'
);

SELECT is(
  (SELECT invited_by_user_id FROM project_members
   WHERE user_id = 'abab2222-2222-2222-2222-222222222222'
     AND project_id = 'abab3333-3333-3333-3333-333333333331'),
  'abab1111-1111-1111-1111-111111111111'::uuid,
  'Converted membership preserves the inviter'
);

SELECT is(
  (SELECT count(*)::int FROM notifications
   WHERE recipient_user_id = 'abab2222-2222-2222-2222-222222222222'
     AND notification_type = 'project_invite'),
  2,
  'One project_invite notification per converted invitation'
);

SELECT is(
  (SELECT status::text FROM project_invitations
   WHERE project_id = 'abab3333-3333-3333-3333-333333333331'
     AND email = 'newbie@example.com'),
  'pending',
  'The invitation row stays pending until the user responds in-app'
);

-- =============================================================================
-- 6. Unrelated pending invitations are untouched
-- =============================================================================
SELECT is(
  (SELECT count(*)::int FROM project_members pm
   JOIN users u ON u.id = pm.user_id
   WHERE u.email = 'someone-else@example.com'),
  0,
  'Invitations for other emails are not converted'
);

-- =============================================================================
-- 7. Non-pending invitations are not converted
-- =============================================================================
DO $$
BEGIN
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code)
    VALUES ('abab4444-4444-4444-4444-444444444444', 'abab4444-0000-0000-0000-000000000004', 'was-declined@example.com', 'Was', 'Declined', 'abab5555-5555-5555-5555-555555555555', 'active', '{}', '+1');
END $$;

SELECT is(
  (SELECT count(*)::int FROM project_members
   WHERE user_id = 'abab4444-4444-4444-4444-444444444444'),
  0,
  'A declined invitation does not convert at signup'
);

-- =============================================================================
-- 8. respond_to_invitation settles the converted invitation
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "abab2222-0000-0000-0000-000000000002"}', true);
SELECT lives_ok(
  $$ SELECT respond_to_invitation('abab3333-3333-3333-3333-333333333331', true) $$,
  'Converted invitee can accept in-app'
);
RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
