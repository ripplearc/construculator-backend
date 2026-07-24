BEGIN;

-- Tests for CA-839: get_project_owners() — distinct creators of the
-- caller-visible projects, exposed for the Owner filter sheets. Covers the
-- RLS-scoped visibility, per-creator deduplication, the pinned (leak-free)
-- return column set, and the unauthenticated zero-rows contract.

SELECT plan(6);

SELECT has_function(
  'public',
  'get_project_owners',
  ARRAY[]::text[],
  'get_project_owners takes no arguments (identity comes from the JWT)'
);

-- Privacy pin: exactly the public-profile subset; a signature change that
-- adds credential_id or email must fail here (prior review caught a
-- credential_id leak on global_search's members block). RETURNS TABLE
-- output columns are pg_proc OUT params, so pin their names directly.
SELECT is(
  (SELECT array_to_string(proargnames, ',') COLLATE "C"
     FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace
       AND proname = 'get_project_owners'),
  'id,first_name,last_name,professional_role,profile_photo_url' COLLATE "C",
  'get_project_owners returns only the public-profile column set'
);

DO $$
DECLARE
  v_viewer_id uuid := '11111111-1111-1111-1111-111111111111';
  v_viewer_credential_id uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_role_id uuid := '55555555-5555-5555-5555-555555555555';
  v_admin_role_id uuid := '66666666-6666-6666-6666-666666666666';
  v_owner_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_owner_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_owner_c uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_project_a1 uuid := '33333333-3333-3333-3333-333333333333';
  v_project_a2 uuid := '44444444-4444-4444-4444-444444444444';
  v_project_b uuid := '77777777-7777-7777-7777-777777777777';
  v_project_c uuid := '99999999-9999-9999-9999-999999999999';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_prof_role_id, 'Test Role');

  -- The viewer lists the owners; the three owners only create projects.
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES
      (v_viewer_id, v_viewer_credential_id, 'owners_rpc_viewer@example.com', 'Owner', 'Viewer', v_prof_role_id, now(), 'active', '{}', '+1'),
      (v_owner_a, gen_random_uuid(), 'owners_rpc_a@example.com', 'Owner', 'Alpha', v_prof_role_id, now(), 'active', '{}', '+1'),
      (v_owner_b, gen_random_uuid(), 'owners_rpc_b@example.com', 'Owner', 'Beta', v_prof_role_id, now(), 'active', '{}', '+1'),
      (v_owner_c, gen_random_uuid(), 'owners_rpc_c@example.com', 'Owner', 'Gamma', v_prof_role_id, now(), 'active', '{}', '+1');

  INSERT INTO roles (id, role_name, level, context_type) VALUES (v_admin_role_id, 'TestAdmin', 4, 'project');
  INSERT INTO role_permissions (role_id, permission_id)
    SELECT v_admin_role_id, id FROM permissions WHERE permission_key IN ('view_project');

  -- Owner A creates TWO visible projects (dedup fixture); owner B one
  -- visible project; owner C's project has no viewer membership and must
  -- therefore contribute no owner row.
  INSERT INTO projects (id, project_name, creator_user_id, project_status)
    VALUES
      (v_project_a1, 'owners rpc project alpha one', v_owner_a, 'active'),
      (v_project_a2, 'owners rpc project alpha two', v_owner_a, 'active'),
      (v_project_b, 'owners rpc project beta', v_owner_b, 'active'),
      (v_project_c, 'owners rpc project gamma', v_owner_c, 'active');

  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
    VALUES
      (v_project_a1, v_viewer_id, v_admin_role_id, 'joined', now()),
      (v_project_a2, v_viewer_id, v_admin_role_id, 'joined', now()),
      (v_project_b, v_viewer_id, v_admin_role_id, 'joined', now());
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{
  "sub": "22222222-2222-2222-2222-222222222222"
}', true);

-- Owners of visible projects only, one row per creator: owner A (despite
-- two projects) and owner B; owner C's project is invisible to the viewer.
SELECT is(
  (SELECT count(*) FROM get_project_owners()),
  2::bigint,
  'Returns one row per distinct creator of the caller-visible projects'
);

SELECT results_eq(
  'SELECT id FROM get_project_owners() ORDER BY id',
  ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[],
  'Returns exactly the creators of the visible projects (invisible project contributes none)'
);

SELECT results_eq(
  'SELECT last_name FROM get_project_owners()',
  ARRAY['Alpha', 'Beta']::character varying[],
  'Rows are ordered by first_name, last_name for a stable sheet ordering'
);

-- Unauthenticated (no JWT claims): the projects RLS predicate is false for
-- a NULL auth.uid(), so no owners leak.
SELECT set_config('request.jwt.claims', NULL, true);
SELECT is(
  (SELECT count(*) FROM get_project_owners()),
  0::bigint,
  'Without an authenticated identity no owners are returned'
);

SELECT * FROM finish();
ROLLBACK;
