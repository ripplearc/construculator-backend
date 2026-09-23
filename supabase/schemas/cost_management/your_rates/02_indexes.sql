-- Your Rates Indexes

-- Collision constraint (Decision 55): two rows can never share the same
-- (company_id, category, item_name, entry_label) grouping+label, including
-- when both entry_labels are NULL. A plain UNIQUE (a,b,c,entry_label) would
-- NOT catch the NULL case -- Postgres treats NULL <> NULL for uniqueness --
-- so entry_label is normalized through COALESCE first. This also doubles as
-- the grouping lookup index (company_id, category, item_name): its leading
-- three columns satisfy that prefix, so no separate index is added.
CREATE UNIQUE INDEX "your_rates_company_category_item_label_idx"
    ON "public"."your_rates" ("company_id", "category", "item_name", COALESCE("entry_label", ''::character varying));
