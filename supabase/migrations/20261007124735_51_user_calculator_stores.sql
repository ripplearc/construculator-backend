-- CA-1076: user_calculator_stores, the calculator's trade stores that follow
-- the user's account (UX Design Doc term 2.16, Appendix B; Calculation
-- Module Design Doc, Appendix E).
--
-- Only the rows the user added or changed live here; the seed defaults ship
-- in the app and are laid over them at read time. One row is one entry of
-- one store (a sheet size, a rate, a named density) as the user typed it,
-- with its fields in the engine's canonical units as a JSON object.
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against (same
-- reason migrations 41-44 were hand-written). Mirrors
-- supabase/schemas/_types/enums.sql and
-- supabase/schemas/calculator/user_calculator_stores/ -- keep them in step.
-- Label 51: 45 and 46 were taken by your_rates (#57) while this sat open.
--
-- Rollback (manual; Supabase migrations are append-only):
--   DROP TABLE public.user_calculator_stores;
--   DROP TYPE public.calculator_store_kind_enum;
-- https://ripplearc.youtrack.cloud/issue/CA-1076

-- ============================================================
-- Enum
-- ============================================================

CREATE TYPE "public"."calculator_store_kind_enum" AS ENUM (
    'sheet_size',
    'masonry_piece',
    'footing_section',
    'on_centre_spacing',
    'fence_config',
    'rate',
    'waste',
    'density'
);


ALTER TYPE "public"."calculator_store_kind_enum" OWNER TO "postgres";

-- ============================================================
-- Table
-- ============================================================

-- user_calculator_stores table
-- The calculator's trade stores (UX Design Doc term 2.16, Appendix B): the
-- editable lists behind the material keys — sheet sizes, masonry piece
-- sizes, footing cross-sections, on-centre spacings, the fence's spacing and
-- rails, rates per unit, waste per unit and named densities. They follow the
-- user's account and are the same on every phone (Appendix E).
--
-- Only the rows the user added or changed live here. The seed defaults of
-- Appendix B ship inside the app and are laid over these rows at read time,
-- so a fresh account has no rows at all and a user who never edits a store
-- never writes one. See README.md.

CREATE TABLE IF NOT EXISTS "public"."user_calculator_stores" (
  "id"           uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  -- Cascades: a trade store is the user's own preference, not an evidence
  -- log like user_consents, so deleting the account takes its rows with it
  -- (company_users.user_id cascades for the same reason).
  "user_id"      uuid NOT NULL REFERENCES "public"."users"("id") ON DELETE CASCADE,
  "store_kind"   "public"."calculator_store_kind_enum" NOT NULL,
  -- The entry's fields in the engine's canonical units (whole ticks of
  -- 1/64 inch, hundredths of a pound, percent, dollars), as one JSON object
  -- whose keys the app's row mapper owns. A changed seed carries the seed's
  -- key in "seed" so the app knows which default it replaces.
  "values"       jsonb NOT NULL,
  -- Which unit system the entry was made under. Sheet sizes are seeded per
  -- system (48in × 96in under Imperial, 1200 × 2400 mm under Metric), so a
  -- user-added size belongs to the system it was typed in.
  "unit_system"  text NOT NULL,
  "created_at"   timestamptz NOT NULL DEFAULT (now()),
  "updated_at"   timestamptz NOT NULL DEFAULT (now()),
  -- Soft delete: the app sets this through an UPDATE. A deleted seed needs
  -- a row to stay behind, carrying the seed's key, or the shipped default
  -- would come back on every phone; user-added rows take the same path so
  -- delete is one code path in the app.
  "deleted_at"   timestamptz,

  CONSTRAINT "user_calculator_stores_unit_system_check"
    CHECK ("unit_system" IN ('imperial', 'metric')),
  -- A row is one entry, so its values are always an object, never a list
  -- or a scalar; the app's mapper relies on it.
  CONSTRAINT "user_calculator_stores_values_object"
    CHECK (jsonb_typeof("values") = 'object')
);

ALTER TABLE "public"."user_calculator_stores" OWNER TO "postgres";

-- ============================================================
-- Indexes
-- ============================================================

-- Indexes for user_calculator_stores

-- The one read the app makes: a user's live rows of one store. Partial on
-- deleted_at so soft-deleted rows cost nothing here; PowerSync reads the
-- table from replicated state, not through this index.
CREATE INDEX IF NOT EXISTS "user_calculator_stores_user_kind_idx"
  ON "public"."user_calculator_stores" ("user_id", "store_kind")
  WHERE "deleted_at" IS NULL;

-- One live row per changed seed. Two phones that edit the same default while
-- offline would otherwise each insert a row, and the two never merge. Keyed
-- on unit_system too because sheet sizes are seeded per system. Rows the
-- user adds themselves carry no "seed" key and stay unrestricted.
CREATE UNIQUE INDEX IF NOT EXISTS "user_calculator_stores_live_seed_key"
  ON "public"."user_calculator_stores" ("user_id", "store_kind", "unit_system", ("values"->>'seed'))
  WHERE "deleted_at" IS NULL AND "values" ? 'seed';

-- ============================================================
-- RLS
-- ============================================================

-- RLS policies for user_calculator_stores
-- Owner only, on every verb. A trade store is personal: no teammate, no
-- project and no company ever reads another user's rates or sheet sizes.
--
-- Keyed on jwt_internal_user_id(), NOT auth.uid(), as user_consents is:
-- auth.uid() returns users.credential_id while user_id here references
-- users.id, so auth.uid() would match nothing and read as "the stores are
-- not syncing" rather than as a bug. The sync stream in
-- powersync/sync-config.yaml filters on the same claim.
--
-- Delete from the app is a soft delete (deleted_at set through an UPDATE).
-- The DELETE policy lets a signed-in client, an API call or an upload, hard
-- delete its own rows and nobody else's; the SQL editor runs as postgres
-- and never passes through it.

ALTER TABLE "public"."user_calculator_stores" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_calculator_stores_select_policy" ON "public"."user_calculator_stores"
  FOR SELECT TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"());

-- WITH CHECK is what stops a user writing a row in someone else's name.
CREATE POLICY "user_calculator_stores_insert_policy" ON "public"."user_calculator_stores"
  FOR INSERT TO "authenticated"
  WITH CHECK ("user_id" = "public"."jwt_internal_user_id"());

CREATE POLICY "user_calculator_stores_update_policy" ON "public"."user_calculator_stores"
  FOR UPDATE TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"())
  WITH CHECK ("user_id" = "public"."jwt_internal_user_id"());

CREATE POLICY "user_calculator_stores_delete_policy" ON "public"."user_calculator_stores"
  FOR DELETE TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"());

-- ============================================================
-- Triggers
-- ============================================================

-- Triggers for user_calculator_stores

-- The conflict rule is "the last upload to arrive wins": the server sets
-- updated_at on every UPDATE, whatever the phone sent, so the column records
-- when the server applied the write rather than what a phone's clock said.
-- INSERT keeps the phone's values; a new row has nothing to conflict with.
CREATE OR REPLACE TRIGGER "set_user_calculator_stores_updated_at"
  BEFORE UPDATE ON "public"."user_calculator_stores"
  FOR EACH ROW EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
