create table "public"."search_history" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "search_term" character varying(255) not null,
    "scope" character varying(50) not null,
    "search_count" integer not null default 1,
    "has_results" boolean not null default false,
    "project_id" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
);


alter table "public"."search_history" enable row level security;

CREATE INDEX search_history_created_at_idx ON public.search_history USING btree (created_at);

CREATE INDEX search_history_has_results_idx ON public.search_history USING btree (has_results) WHERE (has_results = true);

CREATE UNIQUE INDEX search_history_pkey ON public.search_history USING btree (id);

CREATE INDEX search_history_project_id_idx ON public.search_history USING btree (project_id);

CREATE INDEX search_history_user_id_idx ON public.search_history USING btree (user_id);

CREATE UNIQUE INDEX search_history_user_term_scope_uq ON public.search_history USING btree (user_id, search_term, scope);

alter table "public"."search_history" add constraint "search_history_pkey" PRIMARY KEY using index "search_history_pkey";

alter table "public"."search_history" add constraint "search_history_project_id_fkey" FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL not valid;

alter table "public"."search_history" validate constraint "search_history_project_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.get_search_suggestions(user_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_suggestions text[];
BEGIN

  -- Anti-spoof guard: reject calls where the passed user_id does not
  -- match the authenticated session. Prevents parameter spoofing via
  -- the PostgREST API even though RLS would silently return empty rows.
  IF user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: user_id must match the authenticated session'
      USING ERRCODE = '42501';
  END IF;

  -- Step 1: Personal history — own searches that returned results
  SELECT ARRAY(
    SELECT sh.search_term
    FROM search_history sh
    WHERE sh.user_id = auth.uid()
      AND sh.has_results = true
    ORDER BY sh.search_count DESC
    LIMIT 10
  ) INTO v_suggestions;

  IF cardinality(v_suggestions) > 0 THEN
    RETURN v_suggestions;
  END IF;

  -- Step 2: Teammate history — top terms from users sharing a project.
  -- DISTINCT ON picks one row per term (the one with highest search_count).
  -- The outer ORDER BY then sorts those representatives by count DESC.
  SELECT ARRAY(
    SELECT t.search_term
    FROM (
      SELECT DISTINCT ON (sh.search_term)
        sh.search_term,
        sh.search_count
      FROM search_history sh
      WHERE sh.project_id IN (
          SELECT pm.project_id
          FROM project_members pm
          JOIN users u ON pm.user_id = u.id
          WHERE u.credential_id = auth.uid()
            AND pm.membership_status = 'joined'
        )
        AND sh.user_id != auth.uid()
        AND sh.has_results = true
      ORDER BY sh.search_term, sh.search_count DESC
    ) t
    ORDER BY t.search_count DESC
    LIMIT 10
  ) INTO v_suggestions;

  IF cardinality(v_suggestions) > 0 THEN
    RETURN v_suggestions;
  END IF;

  -- Step 3: Nothing found — return empty array
  RETURN ARRAY[]::text[];

END;
$function$
;

CREATE OR REPLACE FUNCTION public.global_search(query text, filter_by_tag text DEFAULT NULL::text, filter_by_date timestamp with time zone DEFAULT NULL::timestamp with time zone, filter_by_owner uuid DEFAULT NULL::uuid, scope text DEFAULT NULL::text, "offset" integer DEFAULT 0, "limit" integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_projects    jsonb := '[]'::jsonb;
  v_estimations jsonb := '[]'::jsonb;
  v_members     jsonb := '[]'::jsonb;
  v_search      text  := '%' || lower(query) || '%';
BEGIN

  -- Validate scope — unknown values would silently return empty results.
  IF scope IS NOT NULL AND scope NOT IN ('dashboard', 'estimation', 'member') THEN
    RAISE EXCEPTION 'Invalid scope: %', scope USING ERRCODE = '22023';
  END IF;

  -- TODO: [CA-596] Wire up filter_by_tag once project-tag schema exists.
  -- https://ripplearc.youtrack.cloud/issue/CA-596
  -- filter_by_tag is reserved for future use. No project-tag join table
  -- exists yet; the parameter is accepted but not applied to any query.

  -- Projects: visible when scope is dashboard or null (all)
  IF scope IS NULL OR scope = 'dashboard' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(p.*)), '[]'::jsonb)
    INTO v_projects
    FROM (
      SELECT
        id,
        project_name,
        description,
        creator_user_id,
        owning_company_id,
        export_folder_link,
        export_storage_provider,
        created_at,
        updated_at,
        project_status AS status
      FROM projects
      WHERE
        (lower(project_name) LIKE v_search OR lower(COALESCE(description, '')) LIKE v_search)
        AND (filter_by_date IS NULL OR created_at >= filter_by_date)
        AND (filter_by_owner IS NULL OR creator_user_id = filter_by_owner)
      ORDER BY updated_at DESC
      LIMIT "limit" OFFSET "offset"
    ) p;
  END IF;

  -- Cost estimates: visible when scope is dashboard, estimation, or null
  IF scope IS NULL OR scope = 'dashboard' OR scope = 'estimation' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb)
    INTO v_estimations
    FROM (
      SELECT
        id,
        project_id,
        estimate_name,
        estimate_description,
        creator_user_id,
        markup_type,
        overall_markup_value_type,
        overall_markup_value,
        material_markup_value_type,
        material_markup_value,
        labor_markup_value_type,
        labor_markup_value,
        equipment_markup_value_type,
        equipment_markup_value,
        total_cost,
        is_locked,
        locked_by_user_id,
        locked_at,
        created_at,
        updated_at
      FROM cost_estimates
      WHERE
        (lower(estimate_name) LIKE v_search OR lower(COALESCE(estimate_description, '')) LIKE v_search)
        AND (filter_by_date IS NULL OR created_at >= filter_by_date)
        AND (filter_by_owner IS NULL OR creator_user_id = filter_by_owner)
      ORDER BY updated_at DESC
      LIMIT "limit" OFFSET "offset"
    ) e;
  END IF;

  -- Members: visible when scope is dashboard, member, or null
  IF scope IS NULL OR scope = 'dashboard' OR scope = 'member' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(m.*)), '[]'::jsonb)
    INTO v_members
    FROM (
      SELECT DISTINCT ON (u.id)
        u.id,
        u.first_name,
        u.last_name,
        u.professional_role,
        u.profile_photo_url
      FROM project_members pm
      JOIN users u ON pm.user_id = u.id
      WHERE
        pm.membership_status = 'joined'
        AND (
          lower(u.first_name) LIKE v_search
          OR lower(u.last_name) LIKE v_search
          OR lower(u.email) LIKE v_search
        )
      ORDER BY u.id, pm.project_id
      LIMIT "limit" OFFSET "offset"
    ) m;
  END IF;

  RETURN jsonb_build_object(
    'projects',    v_projects,
    'estimations', v_estimations,
    'members',     v_members
  );

END;
$function$
;

CREATE OR REPLACE FUNCTION public.increment_search_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.search_count := OLD.search_count + 1;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_search_history_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$
;

grant delete on table "public"."search_history" to "anon";

grant insert on table "public"."search_history" to "anon";

grant references on table "public"."search_history" to "anon";

grant select on table "public"."search_history" to "anon";

grant trigger on table "public"."search_history" to "anon";

grant truncate on table "public"."search_history" to "anon";

grant update on table "public"."search_history" to "anon";

grant delete on table "public"."search_history" to "authenticated";

grant insert on table "public"."search_history" to "authenticated";

grant references on table "public"."search_history" to "authenticated";

grant select on table "public"."search_history" to "authenticated";

grant trigger on table "public"."search_history" to "authenticated";

grant truncate on table "public"."search_history" to "authenticated";

grant update on table "public"."search_history" to "authenticated";

grant delete on table "public"."search_history" to "service_role";

grant insert on table "public"."search_history" to "service_role";

grant references on table "public"."search_history" to "service_role";

grant select on table "public"."search_history" to "service_role";

grant trigger on table "public"."search_history" to "service_role";

grant truncate on table "public"."search_history" to "service_role";

grant update on table "public"."search_history" to "service_role";

create policy "search_history_delete_policy"
on "public"."search_history"
as permissive
for delete
to public
using ((user_id = auth.uid()));


create policy "search_history_insert_policy"
on "public"."search_history"
as permissive
for insert
to public
with check ((user_id = auth.uid()));


create policy "search_history_select_policy"
on "public"."search_history"
as permissive
for select
to public
using ((user_id = auth.uid()));


create policy "search_history_teammate_select_policy"
on "public"."search_history"
as permissive
for select
to public
using (((project_id IS NOT NULL) AND (project_id IN ( SELECT pm.project_id
   FROM (project_members pm
     JOIN users u ON ((pm.user_id = u.id)))
  WHERE ((u.credential_id = auth.uid()) AND (pm.membership_status = 'joined'::membership_status_enum))))));


create policy "search_history_update_policy"
on "public"."search_history"
as permissive
for update
to public
using ((user_id = auth.uid()));


CREATE TRIGGER trigger_increment_search_count BEFORE UPDATE ON public.search_history FOR EACH ROW WHEN (((NOT (old.user_id IS DISTINCT FROM new.user_id)) AND (NOT ((old.search_term)::text IS DISTINCT FROM (new.search_term)::text)) AND (NOT ((old.scope)::text IS DISTINCT FROM (new.scope)::text)))) EXECUTE FUNCTION increment_search_count();

CREATE TRIGGER trigger_set_search_history_updated_at BEFORE UPDATE ON public.search_history FOR EACH ROW EXECUTE FUNCTION set_search_history_updated_at();


