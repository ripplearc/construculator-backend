-- CA-1398: one live row per changed default, whatever unit the user typed.
--
-- user_calculator_stores_live_seed_key (migration 51) keyed the one-live-row
-- rule on unit_system as well as on the seed. The app writes unit_system from
-- the unit the user typed, and masonry, footing, spacing and fence have one
-- set of defaults for both systems, so a default changed in inches on one
-- phone and in millimetres on another gave two live rows the index let
-- through (review of #67, N1). The key is now (user_id, store_kind, seed):
-- sheet seeds already name their system (sheet_48x96in, sheet_1200x2400mm),
-- waste seeds are unit names with one system each, and densities are always
-- imperial, so the seed alone names one default.
--
-- DROP then CREATE: a unique index cannot change its key in place. No row can
-- violate the new key: the app has not synced to this table yet (CA-1083 is
-- open), and the migration fails rather than drops a row if one ever did.
-- Mirrors supabase/schemas/calculator/user_calculator_stores/02_indexes.sql;
-- keep them in step (written by hand, schema_paths = [], as 58).
--
-- Rollback (manual): recreate the index with unit_system back in the key, as
-- migration 51 wrote it.
-- https://ripplearc.youtrack.cloud/issue/CA-1398

DROP INDEX IF EXISTS "public"."user_calculator_stores_live_seed_key";

CREATE UNIQUE INDEX IF NOT EXISTS "user_calculator_stores_live_seed_key"
  ON "public"."user_calculator_stores" ("user_id", "store_kind", ("values"->>'seed'))
  WHERE "deleted_at" IS NULL AND "values" ? 'seed';
