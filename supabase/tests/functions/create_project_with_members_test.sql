BEGIN;

-- CA-808: create_project_with_members RPC (success + rollback-on-failure) and
-- the creator-membership backfill (insert, idempotency, no clobbering).

SELECT plan(13);

-- Seeded role ids: Admin ...01 / Manager ...02 / Collaborator ...03 / Viewer ...04

-- =============================================================================
-- Fixture
-- =============================================================================
DO $$
DECLARE
  v_prof_role_id uuid := 'cdcd5555-5555-5555-5555-555555555555';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'CPM Test Role');
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, user_status, user_preferences, country_code) VALUES
    ('cdcd1111-1111-1111-1111-111111111111', 'cdcd1111-0000-0000-0000-000000000001', 'cpm_creator@example.com', 'Creator', 'User', v_prof_role_id, 'active', '{}', '+1'),
    ('cdcd1111-1111-1111-1111-222222222222', 'cdcd1111-0000-0000-0000-000000000002', 'cpm_member@example.com', 'Invited', 'Member', v_prof_role_id, 'active', '{}', '+1');
END $$;

-- =============================================================================
-- 1-5. Success path: project + creator Admin membership + invites, atomically
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cdcd1111-0000-0000-0000-000000000001"}', true);

CREATE TEMP TABLE cpm_result AS
SELECT create_project_with_members(
  '{"project_name": "cpm success project", "description": "created via RPC"}',
  '[{"email": "cpm_member@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440003"},
    {"email": "cpm-nobody@example.com", "role_id": "a50e8400-e29b-41d4-a716-446655440004"}]'
) AS res;

RESET ROLE;

SELECT is(
  (SELECT jsonb_array_length(res -> 'outcomes') FROM cpm_result),
  2,
  'Returns one outcome per invite'
);

SELECT is(
  (SELECT creator_user_id FROM projects WHERE id = (SELECT (res ->> 'project_id')::uuid FROM cpm_result)),
  'cdcd1111-1111-1111-1111-111111111111'::uuid,
  'Project was created with the caller as creator'
);

SELECT results_eq(
  $$ SELECT role_id, membership_status::text, (joined_at IS NOT NULL)
     FROM project_members
     WHERE project_id = (SELECT (res ->> 'project_id')::uuid FROM cpm_result)
       AND user_id = 'cdcd1111-1111-1111-1111-111111111111' $$,
  $$ VALUES ('a50e8400-e29b-41d4-a716-446655440001'::uuid, 'joined', true) $$,
  'Creator got an Admin joined membership'
);

SELECT is(
  (SELECT membership_status::text FROM project_members
   WHERE project_id = (SELECT (res ->> 'project_id')::uuid FROM cpm_result)
     AND user_id = 'cdcd1111-1111-1111-1111-222222222222'),
  'invited',
  'Registered invitee got an invited membership'
);

SELECT is(
  (SELECT status::text FROM project_invitations
   WHERE project_id = (SELECT (res ->> 'project_id')::uuid FROM cpm_result)
     AND email = 'cpm-nobody@example.com'),
  'pending',
  'Unregistered email got a pending invitation'
);

-- =============================================================================
-- 6-7. Rollback path: an invalid invite aborts the whole creation
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cdcd1111-0000-0000-0000-000000000001"}', true);
SELECT throws_ok(
  $$ SELECT create_project_with_members(
       '{"project_name": "cpm rollback project"}',
       '[{"email": "cpm_member@example.com", "role_id": "00000000-0000-0000-0000-00000000dead"}]') $$,
  '22023', NULL,
  'An unknown invite role aborts the call'
);

RESET ROLE;
SELECT is(
  (SELECT count(*)::int FROM projects WHERE project_name = 'cpm rollback project'),
  0,
  'No project row survives a failed invite (rollback)'
);

-- =============================================================================
-- 8. Missing project_name -> 22023
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "cdcd1111-0000-0000-0000-000000000001"}', true);
SELECT throws_ok(
  $$ SELECT create_project_with_members('{"description": "no name"}', '[]') $$,
  '22023', NULL,
  'project_name is required'
);

-- =============================================================================
-- 9. anon has no EXECUTE
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT create_project_with_members('{"project_name": "anon project"}', '[]') $$,
  '42501', NULL,
  'anon cannot execute create_project_with_members'
);
RESET ROLE;

-- =============================================================================
-- 10-13. Creator-membership backfill: inserts for legacy projects, idempotent,
--        never clobbers an existing creator membership.
--        (Mirrors the backfill statement in migration 44; at db reset the
--        migration ran before seeders, so it applies to nothing locally.)
-- =============================================================================
DO $$
BEGIN
  -- Legacy project: predates the membership model (no creator membership).
  INSERT INTO projects (id, project_name, creator_user_id, created_at)
    VALUES ('cdcd3333-3333-3333-3333-333333333331', 'cpm legacy project', 'cdcd1111-1111-1111-1111-111111111111', now() - interval '90 days');
  -- Legacy project whose creator already has a (non-Admin) membership.
  INSERT INTO projects (id, project_name, creator_user_id)
    VALUES ('cdcd3333-3333-3333-3333-333333333332', 'cpm preexisting project', 'cdcd1111-1111-1111-1111-222222222222');
  INSERT INTO project_members (project_id, user_id, role_id, membership_status)
    VALUES ('cdcd3333-3333-3333-3333-333333333332', 'cdcd1111-1111-1111-1111-222222222222', 'a50e8400-e29b-41d4-a716-446655440004', 'invited');

  -- Run the migration-44 backfill statement.
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, invited_at, joined_at)
  SELECT p.id, p.creator_user_id, (SELECT id FROM roles WHERE role_name = 'Admin' AND context_type = 'project'), 'joined', p.created_at, p.created_at
  FROM projects p
  WHERE NOT EXISTS (
    SELECT 1 FROM project_members pm
    WHERE pm.project_id = p.id AND pm.user_id = p.creator_user_id
  )
  ON CONFLICT (project_id, user_id) DO NOTHING;
END $$;

SELECT results_eq(
  $$ SELECT role_id, membership_status::text FROM project_members
     WHERE project_id = 'cdcd3333-3333-3333-3333-333333333331' $$,
  $$ VALUES ('a50e8400-e29b-41d4-a716-446655440001'::uuid, 'joined') $$,
  'Backfill created an Admin joined membership for the legacy creator'
);

SELECT is(
  (SELECT joined_at FROM project_members WHERE project_id = 'cdcd3333-3333-3333-3333-333333333331'),
  (SELECT created_at FROM projects WHERE id = 'cdcd3333-3333-3333-3333-333333333331'),
  'Backfilled joined_at equals the project''s created_at'
);

-- Second run is a no-op.
DO $$
BEGIN
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, invited_at, joined_at)
  SELECT p.id, p.creator_user_id, (SELECT id FROM roles WHERE role_name = 'Admin' AND context_type = 'project'), 'joined', p.created_at, p.created_at
  FROM projects p
  WHERE NOT EXISTS (
    SELECT 1 FROM project_members pm
    WHERE pm.project_id = p.id AND pm.user_id = p.creator_user_id
  )
  ON CONFLICT (project_id, user_id) DO NOTHING;
END $$;

SELECT is(
  (SELECT count(*)::int FROM project_members WHERE project_id = 'cdcd3333-3333-3333-3333-333333333331'),
  1,
  'Re-running the backfill is a no-op'
);

SELECT results_eq(
  $$ SELECT role_id, membership_status::text FROM project_members
     WHERE project_id = 'cdcd3333-3333-3333-3333-333333333332' $$,
  $$ VALUES ('a50e8400-e29b-41d4-a716-446655440004'::uuid, 'invited') $$,
  'A pre-existing creator membership is left untouched'
);

SELECT * FROM finish();

ROLLBACK;
