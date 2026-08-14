-- CA-963: Add consent_versions — the published version of each consent
-- document, and the current_consent_versions view that resolves which one is
-- in force (highest version whose effective_from has passed). Backs the
-- server-driven versioned consent gate in construculator-app.
--
-- Read-only for clients: SELECT for authenticated, no write policy for any
-- role, so publishing stays a migration-only act.
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against. Mirrors
-- supabase/schemas/consent/consent_versions/ exactly — keep the two in step.
--
-- The user_consents log, consent_action_enum and the jwt_internal_user_id()
-- RLS helper land in a follow-up migration on this ticket.
-- https://ripplearc.youtrack.cloud/issue/CA-963

CREATE TYPE public.consent_type_enum AS ENUM (
  'terms_and_privacy',
  'analytics'
);

ALTER TYPE public.consent_type_enum OWNER TO postgres;

CREATE TABLE IF NOT EXISTS public.consent_versions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consent_type   public.consent_type_enum NOT NULL,
  version        integer NOT NULL,
  document_url   text NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  published_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT consent_versions_type_version_uq UNIQUE (consent_type, version),
  CONSTRAINT consent_versions_version_positive CHECK (version > 0),
  CONSTRAINT consent_versions_document_url_not_blank
    CHECK (length(btrim(document_url)) > 0)
);

ALTER TABLE public.consent_versions OWNER TO postgres;

CREATE OR REPLACE VIEW public.current_consent_versions
WITH (security_invoker = true) AS
SELECT DISTINCT ON (consent_type)
  id,
  consent_type,
  version,
  document_url,
  effective_from,
  published_at
FROM public.consent_versions
WHERE effective_from <= now()
ORDER BY consent_type, version DESC;

ALTER VIEW public.current_consent_versions OWNER TO postgres;

COMMENT ON VIEW public.current_consent_versions IS 'One row per consent_type: the highest version whose effective_from has passed. Query this, not consent_versions, which holds the full publication history. security_invoker, so the consent_versions SELECT policy governs access.';

ALTER TABLE public.consent_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY consent_versions_select_policy ON public.consent_versions
  FOR SELECT TO authenticated
  USING (true);
