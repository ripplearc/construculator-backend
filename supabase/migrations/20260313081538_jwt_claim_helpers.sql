-- Create helper function for RLS policies to check permissions from JWT claims
CREATE OR REPLACE FUNCTION public.jwt_has_project_permission(
  p_project_id uuid,
  p_permission_key text
)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' -> 'projects' -> (p_project_id::text)),
    '[]'::jsonb
  ) ? p_permission_key
$$;
