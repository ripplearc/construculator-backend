-- Indexes for user_calculator_stores

-- The one read the app makes: a user's live rows of one store. Partial on
-- deleted_at so soft-deleted rows cost nothing here; the sync stream reads
-- them through the primary key.
CREATE INDEX IF NOT EXISTS "user_calculator_stores_user_kind_idx"
  ON "public"."user_calculator_stores" ("user_id", "store_kind")
  WHERE "deleted_at" IS NULL;
