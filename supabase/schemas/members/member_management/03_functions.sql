-- Member Management Functions (CA-807)
-- All member mutations go through SECURITY DEFINER RPCs; invariants are
-- checked against the DATABASE, never the JWT (CA-784 "JWT staleness
-- strategy"). See README.md for the invariants table.

-- =============================================================================
-- Internal helper: resolve the caller's internal users.id from auth.uid().
-- Not exposed to API roles.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.internal_user_id_for_auth_uid()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id FROM users WHERE credential_id = auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No user profile found for the authenticated caller'
      USING ERRCODE = '42501';
  END IF;
  RETURN v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.internal_user_id_for_auth_uid() FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- Internal helper: process an invite batch on behalf of an inviter.
-- Not exposed to API roles; called by invite_project_members and
-- create_project_with_members (CA-808).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.process_project_invites(
  p_project_id uuid,
  p_inviter_id uuid,
  p_invites jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_inviter_level int;
  v_invite jsonb;
  v_email text;
  v_role_id uuid;
  v_role_level int;
  v_invitee_id uuid;
  v_membership_status membership_status_enum;
  v_outcomes jsonb := '[]'::jsonb;
  v_result text;
BEGIN
  -- Inviter must be a joined member holding invite_member (database check).
  SELECT r.level INTO v_inviter_level
  FROM project_members pm
  JOIN roles r ON r.id = pm.role_id
  WHERE pm.project_id = p_project_id
    AND pm.user_id = p_inviter_id
    AND pm.membership_status = 'joined'
    AND EXISTS (
      SELECT 1
      FROM role_permissions rp
      JOIN permissions perm ON perm.id = rp.permission_id
      WHERE rp.role_id = pm.role_id
        AND perm.permission_key = 'invite_member'
    );

  IF v_inviter_level IS NULL THEN
    RAISE EXCEPTION 'Caller lacks the invite_member permission on this project'
      USING ERRCODE = '42501';
  END IF;

  IF p_invites IS NULL OR jsonb_typeof(p_invites) <> 'array' OR jsonb_array_length(p_invites) = 0 THEN
    RAISE EXCEPTION 'Invites must be a non-empty array of {email, role_id} objects'
      USING ERRCODE = '22023';
  END IF;

  FOR v_invite IN SELECT * FROM jsonb_array_elements(p_invites) LOOP
    v_email := btrim(v_invite ->> 'email');
    v_role_id := (v_invite ->> 'role_id')::uuid;

    IF v_email IS NULL OR v_email = '' OR v_role_id IS NULL THEN
      RAISE EXCEPTION 'Each invite requires a non-empty email and a role_id'
        USING ERRCODE = '22023';
    END IF;

    SELECT level INTO v_role_level
    FROM roles
    WHERE id = v_role_id AND context_type = 'project';

    IF v_role_level IS NULL THEN
      RAISE EXCEPTION 'Unknown project role %', v_role_id
        USING ERRCODE = '22023';
    END IF;

    -- Level rule: a caller may only grant roles no higher than their own.
    IF v_role_level > v_inviter_level THEN
      RAISE EXCEPTION 'Cannot grant a role above the caller''s own level'
        USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_invitee_id FROM users WHERE lower(email) = lower(v_email) LIMIT 1;

    IF v_invitee_id IS NOT NULL THEN
      SELECT membership_status INTO v_membership_status
      FROM project_members
      WHERE project_id = p_project_id AND user_id = v_invitee_id;

      IF v_membership_status IN ('joined', 'invited') THEN
        v_result := 'already_member';
      ELSE
        IF v_membership_status = 'declined' THEN
          -- A declined membership is eligible for re-invite.
          UPDATE project_members
          SET role_id = v_role_id,
              invited_by_user_id = p_inviter_id,
              invited_at = now(),
              joined_at = NULL,
              membership_status = 'invited'
          WHERE project_id = p_project_id AND user_id = v_invitee_id;
        ELSE
          INSERT INTO project_members (project_id, user_id, role_id, invited_by_user_id, membership_status)
          VALUES (p_project_id, v_invitee_id, v_role_id, p_inviter_id, 'invited');
        END IF;

        -- The Notifications feature renders this row with Accept/Decline.
        INSERT INTO notifications (recipient_user_id, triggering_user_id, related_project_id, notification_type)
        VALUES (v_invitee_id, p_inviter_id, p_project_id, 'project_invite');

        v_result := 'invited';
      END IF;
    ELSE
      -- No account yet: latent invitation, activated at signup (v1: no email).
      INSERT INTO project_invitations (project_id, email, role_id, invited_by_user_id, status)
      VALUES (p_project_id, v_email, v_role_id, p_inviter_id, 'pending')
      ON CONFLICT (project_id, email) DO UPDATE
      SET role_id = EXCLUDED.role_id,
          invited_by_user_id = EXCLUDED.invited_by_user_id,
          invited_at = now(),
          status = 'pending';

      v_result := 'pending_signup';
    END IF;

    v_outcomes := v_outcomes || jsonb_build_object('email', v_email, 'result', v_result);
  END LOOP;

  RETURN v_outcomes;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_project_invites(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- invite_project_members(project_id, invites)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.invite_project_members(
  p_project_id uuid,
  p_invites jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN process_project_invites(p_project_id, internal_user_id_for_auth_uid(), p_invites);
END;
$$;

COMMENT ON FUNCTION public.invite_project_members(uuid, jsonb) IS
'Batch member invite (CA-807). Registered emails become project_members rows (invited) plus a project_invite notification; unregistered emails become pending project_invitations. Permission and level-rule checks read the database, not the JWT.';

REVOKE EXECUTE ON FUNCTION public.invite_project_members(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_project_members(uuid, jsonb) TO authenticated;

-- =============================================================================
-- respond_to_invitation(project_id, accept)
-- =============================================================================
-- search_path includes extensions: the citext type/operators live there on
-- hosted Supabase (locally the schema entry is ignored).
CREATE OR REPLACE FUNCTION public.respond_to_invitation(
  p_project_id uuid,
  p_accept boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
  v_membership_id uuid;
BEGIN
  SELECT id INTO v_membership_id
  FROM project_members
  WHERE project_id = p_project_id
    AND user_id = v_caller_id
    AND membership_status = 'invited'
  FOR UPDATE;

  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'No pending invitation for the caller on this project'
      USING ERRCODE = 'P0002';
  END IF;

  IF p_accept THEN
    UPDATE project_members
    SET membership_status = 'joined', joined_at = now()
    WHERE id = v_membership_id;
  ELSE
    UPDATE project_members
    SET membership_status = 'declined'
    WHERE id = v_membership_id;
  END IF;

  UPDATE project_invitations pi
  SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END::invitation_status_enum
  FROM users u
  WHERE u.id = v_caller_id
    AND pi.project_id = p_project_id
    AND pi.email = u.email::citext
    AND pi.status = 'pending';
END;
$$;

COMMENT ON FUNCTION public.respond_to_invitation(uuid, boolean) IS
'Accept (joined + joined_at) or decline the caller''s own pending project invitation (CA-807). Also settles the originating project_invitations row when one exists.';

REVOKE EXECUTE ON FUNCTION public.respond_to_invitation(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_invitation(uuid, boolean) TO authenticated;

-- Member role change / removal (CA-807 3/4)

-- =============================================================================
-- Internal helper: the role level of a joined member holding a permission on a
-- project, or NULL when they are not a joined member / lack the permission.
-- Not exposed to API roles.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.member_permission_level(
  p_project_id uuid,
  p_user_id uuid,
  p_permission_key text
) RETURNS int
LANGUAGE sql
SET search_path = public
STABLE
AS $$
  SELECT r.level
  FROM project_members pm
  JOIN roles r ON r.id = pm.role_id
  WHERE pm.project_id = p_project_id
    AND pm.user_id = p_user_id
    AND pm.membership_status = 'joined'
    AND EXISTS (
      SELECT 1
      FROM role_permissions rp
      JOIN permissions perm ON perm.id = rp.permission_id
      WHERE rp.role_id = pm.role_id
        AND perm.permission_key = p_permission_key
    )
$$;

REVOKE EXECUTE ON FUNCTION public.member_permission_level(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- update_member_role(project_id, member_user_id, new_role_id): change a
-- member's role. The level rule applies to BOTH the member's current role and
-- the new one; the creator's membership is immutable.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_member_role(
  p_project_id uuid,
  p_member_user_id uuid,
  p_new_role_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
  v_caller_level int;
  v_membership_id uuid;
  v_current_level int;
  v_new_level int;
BEGIN
  v_caller_level := member_permission_level(p_project_id, v_caller_id, 'update_member_role');
  IF v_caller_level IS NULL THEN
    RAISE EXCEPTION 'Caller lacks the update_member_role permission on this project'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (SELECT 1 FROM projects WHERE id = p_project_id AND creator_user_id = p_member_user_id) THEN
    RAISE EXCEPTION 'The project creator''s membership cannot be changed'
      USING ERRCODE = '42501';
  END IF;

  SELECT pm.id, r.level INTO v_membership_id, v_current_level
  FROM project_members pm
  JOIN roles r ON r.id = pm.role_id
  WHERE pm.project_id = p_project_id AND pm.user_id = p_member_user_id
  FOR UPDATE OF pm;

  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'No membership found for this user on this project'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT level INTO v_new_level
  FROM roles
  WHERE id = p_new_role_id AND context_type = 'project';

  IF v_new_level IS NULL THEN
    RAISE EXCEPTION 'Unknown project role %', p_new_role_id
      USING ERRCODE = '22023';
  END IF;

  -- Level rule on both sides: the caller can neither touch a member above
  -- their own level nor promote anyone beyond it.
  IF v_current_level > v_caller_level OR v_new_level > v_caller_level THEN
    RAISE EXCEPTION 'Role change exceeds the caller''s own level'
      USING ERRCODE = '42501';
  END IF;

  UPDATE project_members SET role_id = p_new_role_id WHERE id = v_membership_id;
END;
$$;

COMMENT ON FUNCTION public.update_member_role(uuid, uuid, uuid) IS
'Change a project member''s role (CA-807). Requires update_member_role; the level rule applies to both the current and the new role; the creator''s membership is immutable. Checks read the database, not the JWT.';

REVOKE EXECUTE ON FUNCTION public.update_member_role(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_member_role(uuid, uuid, uuid) TO authenticated;

-- =============================================================================
-- remove_project_member(project_id, member_user_id): remove a member, or leave
-- the project yourself. The creator can never be removed (nor leave).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.remove_project_member(
  p_project_id uuid,
  p_member_user_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
BEGIN
  IF EXISTS (SELECT 1 FROM projects WHERE id = p_project_id AND creator_user_id = p_member_user_id) THEN
    RAISE EXCEPTION 'The project creator cannot be removed from the project'
      USING ERRCODE = '42501';
  END IF;

  -- Self-service exception: any member may remove themselves (leave).
  IF v_caller_id <> p_member_user_id
     AND member_permission_level(p_project_id, v_caller_id, 'remove_member') IS NULL THEN
    RAISE EXCEPTION 'Caller lacks the remove_member permission on this project'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM project_members
  WHERE project_id = p_project_id AND user_id = p_member_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No membership found for this user on this project'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_project_member(uuid, uuid) IS
'Remove a member from a project, or leave it yourself (CA-807). Requires remove_member unless removing your own membership; the creator can never be removed. Checks read the database, not the JWT.';

REVOKE EXECUTE ON FUNCTION public.remove_project_member(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_project_member(uuid, uuid) TO authenticated;

-- =============================================================================
-- Signup conversion of pending invitations (CA-807 4/4)
-- =============================================================================
-- search_path includes extensions: the citext type/operators live there on
-- hosted Supabase (locally the schema entry is ignored).
CREATE OR REPLACE FUNCTION public.convert_pending_invitations()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Notify only for rows actually converted: an already-existing membership
  -- (ON CONFLICT skip) must not produce a duplicate invite notification.
  WITH converted AS (
    INSERT INTO project_members (project_id, user_id, role_id, invited_by_user_id, invited_at, membership_status)
    SELECT pi.project_id, NEW.id, pi.role_id, pi.invited_by_user_id, pi.invited_at, 'invited'
    FROM project_invitations pi
    WHERE pi.email = NEW.email::citext
      AND pi.status = 'pending'
    ON CONFLICT (project_id, user_id) DO NOTHING
    RETURNING project_id, invited_by_user_id
  )
  INSERT INTO notifications (recipient_user_id, triggering_user_id, related_project_id, notification_type)
  SELECT NEW.id, c.invited_by_user_id, c.project_id, 'project_invite'
  FROM converted c;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.convert_pending_invitations() IS
'AFTER INSERT trigger on users (CA-807): converts pending project_invitations matching the new user''s email into invited project_members rows plus project_invite notifications. Invitation rows stay pending until responded to in-app.';

REVOKE EXECUTE ON FUNCTION public.convert_pending_invitations() FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- create_project_with_members (CA-808)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_project_with_members(
  p_project jsonb,
  p_invites jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := internal_user_id_for_auth_uid();
  v_project_name text := btrim(p_project ->> 'project_name');
  v_admin_role_id uuid;
  v_project_id uuid;
  v_outcomes jsonb := '[]'::jsonb;
BEGIN
  IF v_project_name IS NULL OR v_project_name = '' THEN
    RAISE EXCEPTION 'project_name is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_admin_role_id
  FROM roles
  WHERE role_name = 'Admin' AND context_type = 'project';

  IF v_admin_role_id IS NULL THEN
    RAISE EXCEPTION 'Admin role is not seeded'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO projects (project_name, description, owning_company_id, creator_user_id)
  VALUES (
    v_project_name,
    p_project ->> 'description',
    (p_project ->> 'owning_company_id')::uuid,
    v_caller_id
  )
  RETURNING id INTO v_project_id;

  -- The creator joins immediately as Admin; invited_by is NULL by design.
  INSERT INTO project_members (project_id, user_id, role_id, membership_status, joined_at)
  VALUES (v_project_id, v_caller_id, v_admin_role_id, 'joined', now());

  IF p_invites IS NOT NULL AND jsonb_typeof(p_invites) = 'array' AND jsonb_array_length(p_invites) > 0 THEN
    -- Same engine and invariants as invite_project_members; the creator's
    -- fresh Admin membership satisfies its permission check.
    v_outcomes := process_project_invites(v_project_id, v_caller_id, p_invites);
  END IF;

  RETURN jsonb_build_object('project_id', v_project_id, 'outcomes', v_outcomes);
END;
$$;

COMMENT ON FUNCTION public.create_project_with_members(jsonb, jsonb) IS
'Transactionally create a project, the creator''s Admin membership, and the invited members'' rows/invitations (CA-808, enables CA-163). Any invalid invite aborts the whole creation.';

REVOKE EXECUTE ON FUNCTION public.create_project_with_members(jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_project_with_members(jsonb, jsonb) TO authenticated;
