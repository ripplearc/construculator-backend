SET check_function_bodies = false;
CREATE FUNCTION public.get_project_search_suggestions(user_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN

  -- Anti-spoof guard: reject calls where the passed user_id does not
  -- match the authenticated session. Prevents parameter spoofing via
  -- the PostgREST API even though RLS would silently return empty rows.
  IF user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: user_id must match the authenticated session'
      USING ERRCODE = '42501';
  END IF;

  -- Personal history — own searches that returned results.
  -- SELECT ARRAY(subquery) returns '{}'::text[] when the subquery is empty,
  -- never NULL, so no COALESCE fallback is required.
  RETURN ARRAY(
    SELECT psh.search_term
    FROM project_search_history psh
    WHERE psh.user_id = auth.uid()
      AND psh.has_results = true
    ORDER BY psh.search_count DESC
    LIMIT 10
  );

END;
$function$;
COMMENT ON FUNCTION public.get_project_search_suggestions(uuid) IS 'Returns up to 10 search-term suggestions for the Project Search feature.
Accepts user_id uuid — must match auth.uid() or raises 42501.
Step 1: caller own history (has_results=true), ordered by frequency.
Step 2: empty array if no personal history.
SECURITY INVOKER — RLS on project_search_history enforces visibility.
Does NOT expose users.credential_id or any auth identifier.
has_results contract: caller must upsert with has_results=true after a non-empty result set.
Rows with has_results=false are stored but excluded from suggestions.';
CREATE TABLE public.project_search_history (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, search_term character varying(255) NOT NULL, has_results boolean DEFAULT false NOT NULL, search_count integer DEFAULT 1 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.project_search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_search_history ADD CONSTRAINT project_search_history_pkey PRIMARY KEY (id);
CREATE INDEX project_search_history_updated_at_idx ON public.project_search_history (updated_at);
CREATE UNIQUE INDEX project_search_history_user_term_uq ON public.project_search_history (user_id, search_term);
CREATE INDEX project_search_history_user_id_idx ON public.project_search_history (user_id);
CREATE INDEX project_search_history_has_results_idx ON public.project_search_history (has_results) WHERE has_results = true;
CREATE OR REPLACE TRIGGER trigger_increment_project_search_count BEFORE UPDATE ON public.project_search_history FOR EACH ROW WHEN (NOT old.user_id IS DISTINCT FROM new.user_id AND NOT old.search_term::text IS DISTINCT FROM new.search_term::text) EXECUTE FUNCTION public.increment_search_count();
CREATE OR REPLACE TRIGGER trigger_set_project_search_history_updated_at BEFORE UPDATE ON public.project_search_history FOR EACH ROW EXECUTE FUNCTION public.set_search_history_updated_at();
CREATE POLICY project_search_history_delete_policy ON public.project_search_history FOR DELETE USING ((user_id = auth.uid()));
CREATE POLICY project_search_history_insert_policy ON public.project_search_history FOR INSERT WITH CHECK ((user_id = auth.uid()));
CREATE POLICY project_search_history_select_policy ON public.project_search_history FOR SELECT USING ((user_id = auth.uid()));
CREATE POLICY project_search_history_update_policy ON public.project_search_history FOR UPDATE USING ((user_id = auth.uid()));
