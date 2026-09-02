-- current_consent_versions view
-- One row per consent type: the version currently in force. This is what
-- clients read — consent_versions holds every version ever published, so a
-- caller selecting the base table has to pick a row itself, and the Flutter
-- client picked an arbitrary one. See README.md.
--
-- security_invoker so the consent_versions SELECT policy still applies.
-- Postgres 15+; config.toml pins major_version = 15.

CREATE OR REPLACE VIEW "public"."current_consent_versions"
WITH ("security_invoker" = true) AS
SELECT DISTINCT ON ("consent_type")
  "id",
  "consent_type",
  "version",
  "document_url",
  "effective_from",
  "published_at"
FROM "public"."consent_versions"
WHERE "effective_from" <= "now"()
ORDER BY "consent_type", "version" DESC;

ALTER VIEW "public"."current_consent_versions" OWNER TO "postgres";

COMMENT ON VIEW "public"."current_consent_versions" IS 'One row per consent_type: the highest version whose effective_from has passed. Query this, not consent_versions, which holds the full publication history. security_invoker, so the consent_versions SELECT policy governs access.';
