-- CA-1306: Give each saved rate the same id on every phone and in this table.
--
-- Two phones that saved the same rate offline each made a random id for it.
-- The server kept one row, the second phone kept an id the server never saw, and
-- later edits to that id matched no row. The id is now computed from the rate's
-- identity, so a clash is one row saved twice and the last upload wins (the
-- storyboard, CUJ 6: "the change the server receives last wins").
--
-- Identity is company, category, item_name_key, equipment_method and
-- entry_label_key, the same five columns as the unique constraint from migration
-- 60. A second price for the same name and method under another label is a
-- second row with its own id, so "Name this rate" keeps both prices (owner
-- decision on CA-1306 and CA-1336, 2026-11-06, confirmed 2026-11-16). No label
-- and a blank label give the same id.
--
-- The check refuses a write whose id is not the computed one, so a client that
-- makes its own id fails loudly instead of leaving a second copy of the rate.
-- Rows that already exist get their computed id before the check is added, so
-- the migration also runs on a database that has data. The column no longer has
-- a random default: an insert without an id fails with a not-null error instead
-- of a check error on a random id.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";


CREATE OR REPLACE FUNCTION "public"."your_rate_id"(
    "company_id" "uuid",
    "category" "public"."cost_item_type_enum",
    "item_name_key" "text",
    "equipment_method" "public"."equipment_pricing_method_enum",
    "entry_label_key" "text"
) RETURNS "uuid"
    LANGUAGE "sql" IMMUTABLE PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
    SELECT extensions.uuid_generate_v5(
        '8cd2f594-2bb2-4396-ac37-762c9e552c65'::"uuid",
        "company_id"::"text" || '|' || "category"::"text" || '|' || replace(replace("item_name_key", E'\\', E'\\\\'), '|', E'\\|') || '|' || COALESCE("equipment_method"::"text", '') || '|' || replace(replace(COALESCE("entry_label_key", ''), E'\\', E'\\\\'), '|', E'\\|')
    )
$$;


ALTER FUNCTION "public"."your_rate_id"("uuid", "public"."cost_item_type_enum", "text", "public"."equipment_pricing_method_enum", "text") OWNER TO "postgres";


REVOKE EXECUTE ON FUNCTION "public"."your_rate_id"("uuid", "public"."cost_item_type_enum", "text", "public"."equipment_pricing_method_enum", "text") FROM PUBLIC, "anon";


UPDATE "public"."your_rates"
SET "id" = "public"."your_rate_id"("company_id", "category", "item_name_key", "equipment_method", "entry_label_key")
WHERE "id" <> "public"."your_rate_id"("company_id", "category", "item_name_key", "equipment_method", "entry_label_key");


ALTER TABLE "public"."your_rates" ALTER COLUMN "id" DROP DEFAULT;


ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_id_matches_identity" CHECK ("id" = public."your_rate_id"("company_id", "category", "item_name_key", "equipment_method", "entry_label_key"));
