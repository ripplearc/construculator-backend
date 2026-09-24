-- CA-1156: Add the cost_items columns Equipment v2 needs.
--
-- CA-1141 (construculator-app PR #649) changed CostItemDto.toJson()/fromJson()
-- to read/write pricing_method, duration, daily_rate, job_amount,
-- delivery_fee, delivery_fee_status, and rate_status as literal top-level
-- JSON keys on cost_items. None of these columns existed, so submitting any
-- Equipment cost item against the real backend would fail with "Could not
-- find column in schema cache" (or equivalent) once CA-355 wires up
-- submission — not caught earlier because CA-1141-1145's own test suites
-- all run against FakeSupabaseWrapper, which doesn't enforce a real schema.
--
-- All 7 columns are nullable, matching the existing unit_price/quantity/
-- labor_* pattern for type-specific fields on this shared table — an
-- Equipment row uses pricing_method/duration/daily_rate/job_amount, a
-- Material/Labor row leaves them all NULL.
--
-- rate_status uses snake_case values (sample_rate_unverified,
-- own_rate_confirmed, missing) — RateStatus.toJson() on the Dart side was
-- fixed in the same CA-1141 branch to emit an explicit snake_case .value
-- instead of the bare (camelCase) enum .name, matching every other enum
-- column in this schema (see LaborCalculationMethodType's own .value
-- field for the established precedent).
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against (same
-- reason migrations 41-44 were hand-written). The schemas/cost_management/
-- cost_items/*.sql and schemas/_types/enums.sql files are still updated
-- alongside this migration to keep the declarative schema in sync with
-- reality once schema_paths is populated.
--
-- equipment_pricing_method_enum is created conditionally: CA-1145's PR #57
-- (your_rates table) already defines this exact type ('day'/'job', for the
-- same EquipmentPricingMethod Dart enum) for its own equipment_method
-- column. Whichever of the two PRs merges first creates it; the other must
-- not fail by trying to create it again.
--
-- https://ripplearc.youtrack.cloud/issue/CA-1156

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'equipment_pricing_method_enum') THEN
    CREATE TYPE "public"."equipment_pricing_method_enum" AS ENUM (
        'day',
        'job'
    );
    ALTER TYPE "public"."equipment_pricing_method_enum" OWNER TO "postgres";
  END IF;
END
$$;

CREATE TYPE "public"."delivery_fee_status_enum" AS ENUM (
    'unset',
    'estimated',
    'confirmed'
);

ALTER TYPE "public"."delivery_fee_status_enum" OWNER TO "postgres";

CREATE TYPE "public"."rate_status_enum" AS ENUM (
    'sample_rate_unverified',
    'own_rate_confirmed',
    'missing'
);

ALTER TYPE "public"."rate_status_enum" OWNER TO "postgres";

ALTER TABLE ONLY "public"."cost_items"
    ADD COLUMN "pricing_method" "public"."equipment_pricing_method_enum",
    ADD COLUMN "duration" numeric(10,2),
    ADD COLUMN "daily_rate" numeric(18,4),
    ADD COLUMN "job_amount" numeric(18,4),
    ADD COLUMN "delivery_fee" numeric(18,4),
    ADD COLUMN "delivery_fee_status" "public"."delivery_fee_status_enum",
    ADD COLUMN "rate_status" "public"."rate_status_enum";

-- Extend trigger_log_cost_item_edited's tracked-columns WHEN clause to
-- cover the 7 new equipment fields, keeping it in sync with the table per
-- its own doc comment in schemas/cost_management/cost_items/04_triggers.sql.
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
    OLD.delivery_fee_status IS DISTINCT FROM NEW.delivery_fee_status OR
    OLD.rate_status IS DISTINCT FROM NEW.rate_status
  )
)
EXECUTE FUNCTION "public"."log_cost_item_edited"();
