-- consent_versions table
-- Published version of each consent document. Written only by migration —
-- there is no client write path (03_rls.sql). Full publication history is
-- kept, not current state; clients read current_consent_versions (02_views).
-- See README.md.

CREATE TABLE IF NOT EXISTS "public"."consent_versions" (
  "id"             uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "consent_type"   "public"."consent_type_enum" NOT NULL,
  "version"        integer NOT NULL,
  "document_url"   text NOT NULL,
  -- When this version starts binding users; distinct from published_at so a
  -- version can be inserted ahead of time and go live on schedule.
  "effective_from" timestamptz NOT NULL DEFAULT (now()),
  -- Audit metadata only. Never decides the gate.
  "published_at"   timestamptz NOT NULL DEFAULT (now()),

  -- Also the access path for current_consent_versions.
  CONSTRAINT "consent_versions_type_version_uq" UNIQUE ("consent_type", "version"),

  CONSTRAINT "consent_versions_version_positive" CHECK ("version" > 0),

  -- The client throws on a blank document_url and resolves the throw to a
  -- status, not an error — so a blank would fail invisibly. Rejected on write.
  CONSTRAINT "consent_versions_document_url_not_blank"
    CHECK (length(btrim("document_url")) > 0)
);

ALTER TABLE "public"."consent_versions" OWNER TO "postgres";
