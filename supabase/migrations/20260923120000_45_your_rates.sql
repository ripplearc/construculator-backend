-- CA-1145: Add your_rates — the contractor's personal saved-rate book.
--
-- Decision 37 (Estimation v2 design doc): store Your rates per company, in
-- the same table Decision 5 already requires. Decision 55 (2026-09-22):
-- the lookup grouping is (company_id, category, item_name), but that
-- grouping can hold several entries distinguished by entry_label, shown to
-- the contractor so they can tell entries apart instead of the app silently
-- overwriting one.
--
-- Adds equipment_pricing_method_enum (matching the Flutter
-- EquipmentPricingMethod enum's .name wire values: 'day', 'job') and the
-- jwt_user_is_company_member() RLS helper. cost_item_type_enum already
-- exists (supabase/schemas/_types/enums.sql) and is reused directly for
-- category.
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against.
-- Mirrors supabase/schemas/cost_management/your_rates/ and the shared
-- helper in supabase/schemas/_shared/01_functions.sql — keep them in step.
-- https://ripplearc.youtrack.cloud/issue/CA-1145

-- equipment_pricing_method_enum is created conditionally: CA-1156's PR #58
-- (equipment v2 cost_items columns) also defines this exact type
-- ('day'/'job', for the same EquipmentPricingMethod Dart enum) for its own
-- pricing_method column. Whichever of the two PRs merges first creates it;
-- the other must not fail by trying to create it again.

DO $$
BEGIN
  IF to_regtype('public.equipment_pricing_method_enum') IS NULL THEN
    CREATE TYPE "public"."equipment_pricing_method_enum" AS ENUM (
        'day',
        'job'
    );
    ALTER TYPE "public"."equipment_pricing_method_enum" OWNER TO "postgres";
  END IF;
END
$$;

-- RLS helper: is the caller a member (any role) of the given company?
--
-- No existing helper covers company membership -- jwt_internal_user_id()
-- only resolves the caller's own users.id. Added here rather than kept
-- local to your_rates because Material and Labor's own future "Your rates"
-- call sites need the identical check.
--
-- SECURITY DEFINER, not SECURITY INVOKER (a deliberate deviation from
-- jwt_internal_user_id()'s style -- see the PR description for CA-1145).
-- company_users has ROW LEVEL SECURITY enabled with zero policies
-- (20250514131510_enable_rls.sql), so it denies-by-default to every role.
-- A SECURITY INVOKER version of this function, called from an authenticated
-- session, would have its own EXISTS subquery run as `authenticated` and
-- see zero company_users rows regardless of actual membership -- silently
-- failing every your_rates policy closed rather than open. SECURITY
-- DEFINER runs the membership check as this function's owner instead,
-- bypassing that dead end. The pinned search_path matters even more here
-- than on an invoker-rights function, since this one runs with the owner's
-- privileges.
CREATE OR REPLACE FUNCTION "public"."jwt_user_is_company_member"("target_company_id" "uuid")
    RETURNS boolean
    LANGUAGE "sql"
    SECURITY DEFINER
    STABLE
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM "public"."company_users"
    WHERE "company_users"."company_id" = "target_company_id"
      AND "company_users"."user_id" = "public"."jwt_internal_user_id"()
  )
$$;

ALTER FUNCTION "public"."jwt_user_is_company_member"("uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."jwt_user_is_company_member"("uuid") IS 'Shared RLS helper. True when the caller (per jwt_internal_user_id()) belongs to target_company_id via company_users, regardless of role. NULL from jwt_internal_user_id() (claim absent) never matches any company_users.user_id, so an absent claim denies rather than leaks.';

-- New functions in public get EXECUTE for PUBLIC by default, which would
-- let anon call this over RPC. The answer only concerns the caller, and
-- anon always gets false, but RLS policies run as authenticated and need
-- EXECUTE, so only PUBLIC/anon are revoked here.
REVOKE EXECUTE ON FUNCTION "public"."jwt_user_is_company_member"("uuid") FROM "PUBLIC";
REVOKE EXECUTE ON FUNCTION "public"."jwt_user_is_company_member"("uuid") FROM "anon";

CREATE TABLE IF NOT EXISTS "public"."your_rates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "category" "public"."cost_item_type_enum" NOT NULL,
    "item_name" character varying(255) NOT NULL,
    "rate_amount" numeric(18,4) NOT NULL,
    "rate_currency" character varying(20) NOT NULL,
    -- Free text, not a Postgres enum: matches cost_items.unit_measurement,
    -- the existing precedent for storing Unit (Flutter enum) values.
    "unit" character varying(50),
    "equipment_method" "public"."equipment_pricing_method_enum",
    -- Distinguishes multiple entries in the same (company_id, category,
    -- item_name) grouping (Decision 55). NULL is a valid, comparable label
    -- for collision purposes -- see the UNIQUE NULLS NOT DISTINCT constraint
    -- below.
    "entry_label" character varying(100),
    -- Client-supplied, like user_consents.recorded_at: this is domain time
    -- (when the contractor saved the rate), not row-modification time, so it
    -- is not defaulted to now().
    "saved_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."your_rates" OWNER TO "postgres";

-- Primary Key

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_pkey" PRIMARY KEY ("id");

-- Foreign Keys
--
-- No ON DELETE clause, matching companies' other referencing tables: a hard
-- delete of a company is blocked while it still has saved rates.

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");

-- Collision constraint (Decision 55): two rows can never share the same
-- (company_id, category, item_name, entry_label) grouping+label, including
-- when both entry_labels are NULL. NULLS NOT DISTINCT (Postgres 15+) makes
-- two NULLs count as equal for this constraint, unlike a plain UNIQUE, which
-- treats NULL <> NULL. Unlike an expression index on COALESCE(entry_label,
-- ''), this is a real column-list unique constraint, so it can be an
-- upsert(onConflict: ...) target with plain column names, and the leading
-- three columns still serve the group lookup.
ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_company_category_item_label_key"
    UNIQUE NULLS NOT DISTINCT ("company_id", "category", "item_name", "entry_label");

ALTER TABLE "public"."your_rates" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "your_rates_select_policy" ON "public"."your_rates"
    FOR SELECT
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"));

CREATE POLICY "your_rates_insert_policy" ON "public"."your_rates"
    FOR INSERT
    TO "authenticated"
    WITH CHECK ("public"."jwt_user_is_company_member"("company_id"));

CREATE POLICY "your_rates_update_policy" ON "public"."your_rates"
    FOR UPDATE
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"))
    WITH CHECK ("public"."jwt_user_is_company_member"("company_id"));

-- No DELETE policy, deliberately: neither Decision 55 nor the ticket
-- mentions deleting a saved rate. Matches user_consents' own
-- withheld-capability precedent.

CREATE OR REPLACE TRIGGER "trigger_update_your_rates_updated_at"
    BEFORE UPDATE ON "public"."your_rates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
