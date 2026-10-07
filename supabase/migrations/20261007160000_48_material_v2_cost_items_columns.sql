-- CA-1182: Add the cost_items columns Material v2 needs.
--
-- Same class of bug as CA-1156: the Material v2 cost item carries
-- waste_percent, quantity_provenance and calculator_formula (Estimation v2
-- design doc, Data Models, MaterialCostItem), and none of them had a column.
-- Submitting a Material cost item against the real backend would fail with a
-- missing-column error, which the app's FakeSupabaseWrapper tests cannot catch.
--
-- All 3 columns are nullable and additive, matching the type-specific column
-- pattern on this shared table. Equipment and Labor rows leave them NULL.
-- Design doc Decision 29 keeps quantity_provenance and calculator_formula
-- Material-only, so no other item type uses them.
--
-- waste_percent is numeric(5,2). The storyboard accepts 0 to 100 with one
-- decimal place, and the extra scale leaves room. NULL means unset, shown as
-- a dash in the app, and is distinct from an explicit 0.
--
-- quantity_provenance uses snake_case labels, like rate_status_enum. The Dart
-- QuantityProvenance values are manual and fromCalculator.
--
-- calculator_formula is plain text: the display string the calculator
-- produced (for example "47.24in x 94.49in"). The app clears it when the
-- quantity is edited by hand.
--
-- rate_status needs no new column. It was added by CA-1156 as a shared
-- rate_status_enum column with no check tying it to item_type, so Material
-- rows can already store it. The design doc lists rateStatus on Material
-- and Labor as well as Equipment.
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against (same
-- reason migrations 41-47 were hand-written). The schemas/ files are updated
-- alongside this migration to keep the declarative schema in sync.
--
-- Rollback (manual; Supabase migrations are append-only): recreate
-- trigger_log_cost_item_edited without the 3 new columns, then
--   ALTER TABLE public.cost_items
--     DROP COLUMN waste_percent,
--     DROP COLUMN quantity_provenance,
--     DROP COLUMN calculator_formula;
--   DROP TYPE public.quantity_provenance_enum;
--
-- https://ripplearc.youtrack.cloud/issue/CA-1182

CREATE TYPE "public"."quantity_provenance_enum" AS ENUM (
    'manual',
    'from_calculator'
);

ALTER TYPE "public"."quantity_provenance_enum" OWNER TO "postgres";

ALTER TABLE ONLY "public"."cost_items"
    ADD COLUMN "waste_percent" numeric(5,2),
    ADD COLUMN "quantity_provenance" "public"."quantity_provenance_enum",
    ADD COLUMN "calculator_formula" text;

-- Extend trigger_log_cost_item_edited's tracked-columns WHEN clause to cover
-- the 3 new Material fields, per its doc comment in
-- schemas/cost_management/cost_items/04_triggers.sql.
CREATE OR REPLACE TRIGGER "trigger_log_cost_item_edited"
AFTER UPDATE ON "public"."cost_items"
FOR EACH ROW
WHEN (
  NOT (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL) AND
  (
    OLD.item_type IS DISTINCT FROM NEW.item_type OR
    OLD.item_name IS DISTINCT FROM NEW.item_name OR
    OLD.unit_price IS DISTINCT FROM NEW.unit_price OR
    OLD.quantity IS DISTINCT FROM NEW.quantity OR
    OLD.unit_measurement IS DISTINCT FROM NEW.unit_measurement OR
    OLD.calculation IS DISTINCT FROM NEW.calculation OR
    OLD.item_total_cost IS DISTINCT FROM NEW.item_total_cost OR
    OLD.currency IS DISTINCT FROM NEW.currency OR
    OLD.brand IS DISTINCT FROM NEW.brand OR
    OLD.product_link IS DISTINCT FROM NEW.product_link OR
    OLD.description IS DISTINCT FROM NEW.description OR
    OLD.labor_calc_method IS DISTINCT FROM NEW.labor_calc_method OR
    OLD.labor_days IS DISTINCT FROM NEW.labor_days OR
    OLD.labor_hours IS DISTINCT FROM NEW.labor_hours OR
    OLD.labor_unit_type IS DISTINCT FROM NEW.labor_unit_type OR
    OLD.labor_unit_value IS DISTINCT FROM NEW.labor_unit_value OR
    OLD.crew_size IS DISTINCT FROM NEW.crew_size OR
    OLD.pricing_method IS DISTINCT FROM NEW.pricing_method OR
    OLD.duration IS DISTINCT FROM NEW.duration OR
    OLD.daily_rate IS DISTINCT FROM NEW.daily_rate OR
    OLD.job_amount IS DISTINCT FROM NEW.job_amount OR
    OLD.delivery_fee IS DISTINCT FROM NEW.delivery_fee OR
    OLD.rate_status IS DISTINCT FROM NEW.rate_status OR
    OLD.waste_percent IS DISTINCT FROM NEW.waste_percent OR
    OLD.quantity_provenance IS DISTINCT FROM NEW.quantity_provenance OR
    OLD.calculator_formula IS DISTINCT FROM NEW.calculator_formula
  )
)
EXECUTE FUNCTION "public"."log_cost_item_edited"();
