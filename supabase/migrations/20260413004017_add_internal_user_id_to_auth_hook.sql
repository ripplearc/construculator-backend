-- Add internal_user_id to custom access token hook
-- This allows triggers to set user ID fields (like locked_by_user_id) without database lookups

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claims jsonb;
  projects_claims jsonb;
  user_internal_id uuid;
BEGIN
  claims := event->'claims';

  -- Get the internal user ID (users.id) from credential_id
  SELECT u.id INTO user_internal_id
  FROM public.users u
  WHERE u.credential_id = (event->>'user_id')::uuid;

  IF user_internal_id IS NULL THEN
  RAISE WARNING 'custom_access_token_hook: no users row for credential_id %',
    (event->>'user_id')::uuid;
  END IF;

  SELECT COALESCE(
    jsonb_object_agg(project_permissions.project_id, project_permissions.permissions),
    '{}'::jsonb
  )
  INTO projects_claims
  FROM (
    SELECT
      pm.project_id::text AS project_id,
      jsonb_agg(DISTINCT p.permission_key ORDER BY p.permission_key) AS permissions
    FROM public.project_members pm
    JOIN public.users u ON u.id = pm.user_id
    JOIN public.role_permissions rp ON rp.role_id = pm.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE u.credential_id = (event->>'user_id')::uuid
      AND pm.membership_status = 'joined'
    GROUP BY pm.project_id
  ) AS project_permissions;

  -- Ensure app_metadata exists, then merge in projects and internal_user_id
  -- This handles cases where claims don't yet have app_metadata (e.g., first login)
  claims := jsonb_set(
    claims,
    '{app_metadata}',
    COALESCE(claims->'app_metadata', '{}'::jsonb) || jsonb_build_object(
      'projects', projects_claims,
      'internal_user_id', user_internal_id
    ),
    true
  );

  RETURN jsonb_build_object('claims', claims);
EXCEPTION WHEN OTHERS THEN
  -- Log the error and return unmodified event rather than empty claims
  RAISE WARNING 'custom_access_token_hook failed for user %: %',
    (event->>'user_id')::uuid, SQLERRM;
  -- Return original event to prevent login failures due to hook errors
  RETURN event;
END;
$$;
