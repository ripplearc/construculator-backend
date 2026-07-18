-- Member Management Triggers

-- Signup conversion (CA-807): when a users row is created for an email with
-- pending project_invitations, convert them into invited memberships.
-- Defined on public.users; owned by this module because it implements the
-- invitation lifecycle.
CREATE OR REPLACE TRIGGER "trigger_convert_pending_invitations"
  AFTER INSERT ON "public"."users"
  FOR EACH ROW
  EXECUTE FUNCTION "public"."convert_pending_invitations"();
