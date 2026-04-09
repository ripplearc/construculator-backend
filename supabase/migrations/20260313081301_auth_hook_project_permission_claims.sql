-- Create custom access token hook for injecting project permissions into JWT
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claims jsonb;
  projects_claims jsonb;
BEGIN
  claims := event->'claims';

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

  -- Ensure app_metadata exists, then merge in projects
  -- This handles cases where claims don't yet have app_metadata (e.g., first login)
  claims := jsonb_set(
    claims,
    '{app_metadata}',
    COALESCE(claims->'app_metadata', '{}'::jsonb) || jsonb_build_object('projects', projects_claims),
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

-- Grant necessary permissions to supabase_auth_admin
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM authenticated, anon, public;
