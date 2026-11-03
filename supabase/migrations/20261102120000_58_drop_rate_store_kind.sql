-- CA-1398: drop the rate kind from calculator_store_kind_enum.
--
-- CA-1304 (decided 28 Oct 2026) keeps one rate list, your_rates, owned by the
-- company: the calculator reads and saves its rates through an interface that
-- estimation implements over that table. user_calculator_stores keeps only the
-- non-rate stores, so the enum loses 'rate'. waste stays: it is a percent the
-- calculator applies to a cost, not a price, and your_rates has no column for
-- it.
--
-- Postgres cannot remove one value from an enum, so the type is recreated:
-- 1. Delete any row of the dropped kind, so the cast in step 3 cannot fail.
--    None is expected: the app has not synced to this table yet (CA-1083 is
--    still open), and a row that did exist would belong to a rate list that no
--    longer lives here.
-- 2. Create the new type with the seven remaining kinds, in the old order.
-- 3. Switch the column to the new type. ALTER COLUMN ... TYPE rebuilds the two
--    indexes that include store_kind (user_calculator_stores_user_kind_idx and
--    user_calculator_stores_live_seed_key); the four RLS policies, the
--    updated_at trigger and the powersync publication never name the column's
--    type and carry over unchanged. The sync stream in
--    powersync/sync-config.yaml lists the column, not its type, and needs no
--    change.
-- 4. Drop the old type and give the new one the old name, so every reference
--    by name (the schema mirror, the pgTAP test, the app's wire values) holds.
--
-- Written by hand: config.toml declares schema_paths = [], so the CLI has no
-- declared schema to diff against (same reason as 51, this table's own
-- migration, and 55). Mirrors supabase/schemas/_types/enums.sql; keep them in
-- step. Label 58: 57 is taken by the open #66 (CA-1261).
--
-- Rollback (manual; Supabase migrations are append-only): recreate the type the
-- same way with 'rate' back between 'fence_config' and 'waste'. No row is
-- restored; the deleted rows were rates, which now live in your_rates.
-- https://ripplearc.youtrack.cloud/issue/CA-1398

DELETE FROM "public"."user_calculator_stores"
 WHERE "store_kind" = 'rate';

CREATE TYPE "public"."calculator_store_kind_enum_v2" AS ENUM (
    'sheet_size',
    'masonry_piece',
    'footing_section',
    'on_centre_spacing',
    'fence_config',
    'waste',
    'density'
);

ALTER TYPE "public"."calculator_store_kind_enum_v2" OWNER TO "postgres";

ALTER TABLE "public"."user_calculator_stores"
  ALTER COLUMN "store_kind" TYPE "public"."calculator_store_kind_enum_v2"
  USING ("store_kind"::text::"public"."calculator_store_kind_enum_v2");

DROP TYPE "public"."calculator_store_kind_enum";

ALTER TYPE "public"."calculator_store_kind_enum_v2"
  RENAME TO "calculator_store_kind_enum";
