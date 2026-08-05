-- CA-839: Add get_project_owners RPC — distinct creators of the
-- caller-visible projects (SECURITY INVOKER over projects RLS; profile
-- columns via the public user_profiles view) for the Owner filter
-- sheets in global search and dashboard project search.
-- Generated via `supabase db diff --from=migrations --to=local` from
-- supabase/schemas/global_search/project_owners/03_functions.sql per
-- the global_search module README workflow; SECURITY INVOKER made
-- explicit post-generation (pg_dump omits it as the default and review
-- asked for it to be spelled out).
-- https://ripplearc.youtrack.cloud/issue/CA-839

SET check_function_bodies = false;
CREATE FUNCTION public.get_project_owners()
 RETURNS TABLE(id uuid, first_name character varying, last_name character varying, professional_role uuid, profile_photo_url text)
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
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
  ORDER BY first_name, last_name, id;
$function$;
GRANT ALL ON FUNCTION public.get_project_owners() TO anon;
GRANT ALL ON FUNCTION public.get_project_owners() TO authenticated;
GRANT ALL ON FUNCTION public.get_project_owners() TO service_role;
