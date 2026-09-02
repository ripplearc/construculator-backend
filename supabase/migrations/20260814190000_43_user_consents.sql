-- CA-963: Add user_consents — the append-only log of consent decisions,
-- withdrawals as well as acceptances. Completes the consent schema begun in
-- migration 41 (consent_versions).
--
-- Adds consent_action_enum and the jwt_internal_user_id() RLS helper, which
-- exists because auth.uid() returns users.credential_id while user_consents.
-- user_id references users.id — a policy on auth.uid() matches nothing and the
-- symptom looks like broken sync rather than a bug.
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against.
-- Mirrors supabase/schemas/consent/user_consents/ and the shared helper in
-- supabase/schemas/_shared/01_functions.sql — keep them in step.
-- https://ripplearc.youtrack.cloud/issue/CA-963

CREATE TYPE public.consent_action_enum AS ENUM (
  'accepted',
  'withdrawn'
);

ALTER TYPE public.consent_action_enum OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.jwt_internal_user_id()
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
STABLE
-- Pinned like every other function in this repo. auth.jwt() is already
-- schema-qualified, so 'public' alone is sufficient; the pin exists so a
-- future edit adding an unqualified reference cannot silently resolve
-- against a caller-controlled search_path from inside two RLS policies.
SET search_path TO 'public'
AS $$
  SELECT NULLIF(auth.jwt() -> 'app_metadata' ->> 'internal_user_id', '')::uuid
$$;

ALTER FUNCTION public.jwt_internal_user_id() OWNER TO postgres;

COMMENT ON FUNCTION public.jwt_internal_user_id() IS 'Shared RLS helper. Returns the caller''s public.users.id from the JWT app_metadata.internal_user_id claim, or NULL when the claim is absent. Use instead of auth.uid() on tables keyed by users.id -- auth.uid() resolves to users.credential_id and never matches. NULL never equals a NOT NULL user_id, so an absent claim denies rather than leaks.';

CREATE TABLE IF NOT EXISTS public.user_consents (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- No ON DELETE clause, matching every other users(id) FK here: a hard
  -- delete of the user is blocked while consent rows exist. The log is
  -- evidence and must not cascade away with the row it describes.
  user_id      uuid NOT NULL REFERENCES public.users(id),
  consent_type public.consent_type_enum NOT NULL,
  version      integer NOT NULL,
  action       public.consent_action_enum NOT NULL,
  -- Client-supplied on every insert, so the DEFAULT is a fallback that never
  -- fires in practice. Bounded on the future side only: this column orders the
  -- history and the newest row decides the gate, so a future-dated 'accepted'
  -- row would outrank every later withdrawal. The past is deliberately
  -- unbounded -- an offline decision may sync arbitrarily late (CA-971).
  recorded_at  timestamptz NOT NULL DEFAULT now(),
  app_version  text,
  platform     text,
  -- >= 0, not > 0: a withdrawal with nothing on file to revoke records 0.
  CONSTRAINT user_consents_version_non_negative CHECK (version >= 0),
  -- One day of slack absorbs device clock skew without admitting a row that
  -- can never be superseded.
  CONSTRAINT user_consents_recorded_at_not_future
    CHECK (recorded_at <= now() + interval '1 day')
);

ALTER TABLE public.user_consents OWNER TO postgres;

CREATE INDEX IF NOT EXISTS user_consents_user_type_recorded_idx
  ON public.user_consents (user_id, consent_type, recorded_at DESC);

ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_consents_select_policy ON public.user_consents
  FOR SELECT TO authenticated
  USING (user_id = public.jwt_internal_user_id());

CREATE POLICY user_consents_insert_policy ON public.user_consents
  FOR INSERT TO authenticated
  WITH CHECK (user_id = public.jwt_internal_user_id());

-- No UPDATE or DELETE policy, deliberately: the log is append-only.
