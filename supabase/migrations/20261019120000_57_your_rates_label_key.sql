-- CA-1261: Make the Your rates label match the way the item name does.
--
-- Decision 55 and the storyboard (CUJ 6) say a saved price is told apart by a
-- short label, and that two labels are the same label when they differ only by
-- capital letters or extra spaces. The phone already compares labels that way.
-- This table did not: the unique constraint compared entry_label as typed, so
-- "With operator" and "with operator" were two rows on the server and one on
-- the phone.
--
-- entry_label_key is the label the way the other saves are matched against it:
-- lower case, every run of whitespace (spaces, tabs, new lines, non-breaking
-- spaces) collapsed to one space, outer spaces trimmed, and NULL when nothing
-- is left. It is built like item_name_key. entry_label keeps the user's own
-- spelling for display. The key is never written by a client.
--
-- The unique constraint keeps its name and its NULLS NOT DISTINCT rule, and
-- compares entry_label_key in place of entry_label. A label of only spaces now
-- counts as no label, the same as the phone treats it.
--
-- The user_rates stream in powersync/sync-config.yaml lists its columns and
-- does not list the new one. The phone computes the key itself, so no sync
-- config change is needed.
--
-- ADD COLUMN puts the column last. The schema mirror lists it last too.
--
-- If two rows of one company already differ only by the case or spacing of
-- their label, adding the constraint fails with a unique violation naming the
-- constraint. Merge or relabel those rows, then run this migration again.
--
-- Written by hand like migration 45. Mirrors
-- supabase/schemas/cost_management/your_rates/01_table.sql, keep them in step.
--
-- Rollback (manual, Supabase migrations are append-only), in this order:
--   1. ALTER TABLE public.your_rates
--        DROP CONSTRAINT your_rates_company_category_name_method_label_key;
--   2. ALTER TABLE public.your_rates ADD CONSTRAINT
--        your_rates_company_category_name_method_label_key UNIQUE NULLS NOT
--        DISTINCT (company_id, category, item_name_key, equipment_method,
--        entry_label);
--   3. ALTER TABLE public.your_rates DROP COLUMN entry_label_key;
-- https://ripplearc.youtrack.cloud/issue/CA-1261

ALTER TABLE "public"."your_rates"
    ADD COLUMN IF NOT EXISTS "entry_label_key" "text" GENERATED ALWAYS AS (NULLIF(lower(btrim(regexp_replace("entry_label", '[\s\u00a0]+', ' ', 'g'))), '')) STORED;

ALTER TABLE ONLY "public"."your_rates"
    DROP CONSTRAINT IF EXISTS "your_rates_company_category_name_method_label_key";

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_company_category_name_method_label_key"
    UNIQUE NULLS NOT DISTINCT ("company_id", "category", "item_name_key", "equipment_method", "entry_label_key");
