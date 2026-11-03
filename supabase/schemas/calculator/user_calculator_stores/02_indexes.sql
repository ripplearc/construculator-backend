-- Indexes for user_calculator_stores

-- The one read the app makes: a user's live rows of one store. Partial on
-- deleted_at so soft-deleted rows cost nothing here; PowerSync reads the
-- table from replicated state, not through this index.
CREATE INDEX IF NOT EXISTS "user_calculator_stores_user_kind_idx"
  ON "public"."user_calculator_stores" ("user_id", "store_kind")
  WHERE "deleted_at" IS NULL;

-- One live row per changed seed. Two phones that edit the same default while
-- offline would otherwise each insert a row, and the two never merge. The seed
-- alone names the default: sheet seeds carry their system in the name
-- (sheet_48x96in, sheet_1200x2400mm), and the other stores have one set of
-- defaults for both systems, so unit_system is not part of the key (59). Rows
-- the user adds themselves carry no "seed" key and stay unrestricted.
CREATE UNIQUE INDEX IF NOT EXISTS "user_calculator_stores_live_seed_key"
  ON "public"."user_calculator_stores" ("user_id", "store_kind", ("values"->>'seed'))
  WHERE "deleted_at" IS NULL AND "values" ? 'seed';
