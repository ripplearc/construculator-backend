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
