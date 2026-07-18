-- CA-807 (4/4): signup conversion of pending invitations. When a users row is
-- created for an email that has pending project_invitations, each converts
-- into a project_members(status='invited') row plus a project_invite
-- notification. The invitation row itself stays 'pending' until the user
-- accepts or declines in-app (respond_to_invitation settles it).

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

CREATE OR REPLACE TRIGGER "trigger_convert_pending_invitations"
  AFTER INSERT ON "public"."users"
  FOR EACH ROW
  EXECUTE FUNCTION "public"."convert_pending_invitations"();
