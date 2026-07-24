-- Functions for the project-owners filter (Owner filter sheets in global
-- search and dashboard project search).

-- ============================================================
-- get_project_owners RPC
--
-- Parameters: none — identity is derived from the Supabase auth session
-- JWT (auth.uid() via RLS), so no explicit user id param is required.
--
-- Returns: one row per distinct creator of the projects the caller can
-- see, ordered by first_name, last_name for a stable sheet ordering.
--
-- SECURITY INVOKER: project visibility comes from the projects RLS
-- policy (user_has_project_permission(id, 'view_project', auth.uid())) —
-- this function does not bypass RLS. The profile columns are read
-- through the user_profiles view, the deliberate public subset of
-- users (the view runs with its owner's rights, which is what makes
-- peers' names visible despite users' select-own RLS).
--
-- Privacy: the return signature pins exactly
-- id, first_name, last_name, professional_role, profile_photo_url.
-- Never add users.credential_id or email here (prior review caught a
-- credential_id leak on global_search's members block; the pgTAP
-- function_returns test pins this column set).
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_project_owners()
 RETURNS TABLE(
   id uuid,
   first_name character varying,
   last_name character varying,
   professional_role uuid,
   profile_photo_url text
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT
    up.id,
    up.first_name,
    up.last_name,
    up.professional_role,
    up.profile_photo_url
  FROM projects p
  JOIN user_profiles up ON up.id = p.creator_user_id
  ORDER BY first_name, last_name;
$function$;
