-- Your Rates Table
-- The contractor's personal saved-rate book, scoped per company (Decision 37).

CREATE TABLE IF NOT EXISTS "public"."your_rates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "category" "public"."cost_item_type_enum" NOT NULL,
    "item_name" character varying(255) NOT NULL,
    -- The name as the contractor's other saves are matched against it: lower
    -- case, runs of whitespace (tabs, new lines, non-breaking spaces) collapsed to
    -- one space, then outer spaces trimmed ("Names match without regard to capital letters or extra
    -- spaces", storyboard CUJ 6). item_name keeps the user's own spelling for
    -- display. A stored generated column, not an expression index, so the
    -- unique constraint below can still be an upsert target.
    "item_name_key" "text" GENERATED ALWAYS AS (lower(btrim(regexp_replace("item_name", '[\s\u00a0]+', ' ', 'g')))) STORED NOT NULL,
    "rate_amount" numeric(18,4) NOT NULL,
    "rate_currency" character varying(20) NOT NULL,
    -- Free text, not a Postgres enum: matches cost_items.unit_measurement,
    -- the existing precedent for storing Unit (Flutter enum) values.
    "unit" character varying(50),
    "equipment_method" "public"."equipment_pricing_method_enum",
    -- Distinguishes multiple entries in the same (company_id, category,
    -- item_name_key, equipment_method) grouping (Decision 55). NULL is a valid, comparable label
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
-- (company_id, category, item_name_key, equipment_method, entry_label), including
-- when equipment_method or entry_label is NULL on both. equipment_method is part
-- of the key because one name can be saved with a day rate and with a job price
-- ("Saved with both", storyboard CUJ 6): those are two rows. NULLS NOT DISTINCT
-- (Postgres 15+) makes two NULLs count as equal for this constraint, unlike a
-- plain UNIQUE, which treats NULL <> NULL. Unlike an expression index on
-- COALESCE(entry_label, ''), this is a real column-list unique constraint, so it
-- can be an upsert(onConflict: ...) target with plain column names, and the
-- leading columns still serve the group lookup.
ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_company_category_name_method_label_key"
    UNIQUE NULLS NOT DISTINCT ("company_id", "category", "item_name_key", "equipment_method", "entry_label");

-- Row rules, so another client cannot save rows the app never would.
ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_item_name_not_blank" CHECK (length("item_name_key") > 0),
    ADD CONSTRAINT "your_rates_rate_amount_not_negative" CHECK ("rate_amount" >= 0),
    ADD CONSTRAINT "your_rates_rate_currency_not_blank" CHECK (length(btrim("rate_currency")) > 0),
    ADD CONSTRAINT "your_rates_equipment_method_equipment_only" CHECK ("equipment_method" IS NULL OR "category" = 'equipment');
