BEGIN;

-- CA-807 (2/4): respond_to_invitation RPC — accept, decline, invitation-row
-- settlement, and error paths.

SELECT plan(9);

-- =============================================================================
-- Fixture: creator + three invited users (userC's invite originated from a
-- project_invitations row, as after signup conversion)
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'dddd5555-5555-5555-5555-555555555555';
  v_project_id uuid := 'dddd3333-3333-3333-3333-333333333333';
  v_creator_id uuid := 'dddd1111-1111-1111-1111-111111111111';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Respond RPC Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code) VALUES
    (v_creator_id, 'dddd1111-0000-0000-0000-000000000001', 'resp_creator@example.com', 'Creator', 'User', v_prof_role_id, 'active', '{}', '+1'),
    ('dddd1111-1111-1111-1111-222222222222', 'dddd1111-0000-0000-0000-000000000002', 'resp_user_a@example.com', 'UserA', 'Invitee', v_prof_role_id, 'active', '{}', '+1'),
    ('dddd1111-1111-1111-1111-333333333333', 'dddd1111-0000-0000-0000-000000000003', 'resp_user_b@example.com', 'UserB', 'Invitee', v_prof_role_id, 'active', '{}', '+1'),
    ('dddd1111-1111-1111-1111-444444444444', 'dddd1111-0000-0000-0000-000000000004', 'resp_user_c@example.com', 'UserC', 'Invitee', v_prof_role_id, 'active', '{}', '+1');

  INSERT INTO projects (id, project_name, creator_user_id) VALUES (v_project_id, 'respond rpc test project', v_creator_id);

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES (v_project_id, v_creator_id, 'a50e8400-e29b-41d4-a716-446655440001', 'joined', now());
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, invited_by_user_id) VALUES
    (v_project_id, 'dddd1111-1111-1111-1111-222222222222', 'a50e8400-e29b-41d4-a716-446655440004', 'invited', v_creator_id),
    (v_project_id, 'dddd1111-1111-1111-1111-333333333333', 'a50e8400-e29b-41d4-a716-446655440004', 'invited', v_creator_id),
    (v_project_id, 'dddd1111-1111-1111-1111-444444444444', 'a50e8400-e29b-41d4-a716-446655440003', 'invited', v_creator_id);

  -- UserC's membership originated from an unregistered-email invitation.
  INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id, status)
    VALUES (v_project_id, 'resp_user_c@example.com', 'a50e8400-e29b-41d4-a716-446655440003', v_creator_id, 'pending');
END $$;

SET LOCAL ROLE authenticated;

-- =============================================================================
-- 1-2. Accept: membership becomes joined with joined_at set
-- =============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "dddd1111-0000-0000-0000-000000000002"}', true);
SELECT lives_ok(
  $$ SELECT respond_to_invitation('dddd3333-3333-3333-3333-333333333333', true) $$,
  'Invited user can accept their invitation'
);

RESET ROLE;
SELECT results_eq(
  $$ SELECT membership_status::text, (joined_at IS NOT NULL) FROM project_members
     WHERE project_id = 'dddd3333-3333-3333-3333-333333333333'
       AND user_id = 'dddd1111-1111-1111-1111-222222222222' $$,
  $$ VALUES ('joined', true) $$,
  'Accepted membership is joined with joined_at set'
);

-- =============================================================================
-- 3. Decline: membership becomes declined
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddd1111-0000-0000-0000-000000000003"}', true);
SELECT lives_ok(
  $$ SELECT respond_to_invitation('dddd3333-3333-3333-3333-333333333333', false) $$,
  'Invited user can decline their invitation'
);

RESET ROLE;
SELECT is(
  (SELECT membership_status::text FROM project_members
   WHERE project_id = 'dddd3333-3333-3333-3333-333333333333'
     AND user_id = 'dddd1111-1111-1111-1111-333333333333'),
  'declined',
  'Declined membership is marked declined'
);

-- =============================================================================
-- 4-5. Accepting settles the originating project_invitations row
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddd1111-0000-0000-0000-000000000004"}', true);
SELECT lives_ok(
  $$ SELECT respond_to_invitation('dddd3333-3333-3333-3333-333333333333', true) $$,
  'Conversion-origin invitee can accept'
);

RESET ROLE;
SELECT is(
  (SELECT membership_status::text FROM project_members
   WHERE project_id = 'dddd3333-3333-3333-3333-333333333333'
     AND user_id = 'dddd1111-1111-1111-1111-444444444444'),
  'joined',
  'Conversion-origin membership is joined after accept'
);
SELECT is(
  (SELECT status::text FROM project_invitations
   WHERE project_id = 'dddd3333-3333-3333-3333-333333333333'
     AND email = 'resp_user_c@example.com'),
  'accepted',
  'The originating project_invitations row is marked accepted'
);

-- =============================================================================
-- 6. No pending invitation -> P0002
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "dddd1111-0000-0000-0000-000000000002"}', true);
SELECT throws_ok(
  $$ SELECT respond_to_invitation('dddd3333-3333-3333-3333-333333333333', true) $$,
  'P0002', NULL,
  'Responding twice (no pending invitation) raises P0002'
);

-- =============================================================================
-- 7. anon has no EXECUTE on the RPC
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT respond_to_invitation('dddd3333-3333-3333-3333-333333333333', true) $$,
  '42501', NULL,
  'anon cannot execute respond_to_invitation'
);
RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
