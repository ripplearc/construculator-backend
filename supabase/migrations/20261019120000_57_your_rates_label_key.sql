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
-- lower case, every run of whitespace collapsed to one space, outer spaces
-- trimmed, and NULL when nothing is left. entry_label keeps the user's own
-- spelling for display. The key is never written by a client.
--
-- The phone builds the same key with Dart's \s, which also counts U+00A0, U+2007
-- (figure space), U+202F (narrow no-break space) and U+FEFF as space and trims
-- U+0085 at the ends. Postgres \s does not, so those are listed here. Apple
-- phones put U+202F in times such as "5 PM". Rare capital letters (Cherokee,
-- Osage, Adlam) are lower-cased differently by Postgres and Dart and are not
-- covered here.
--
-- item_name_key gets the same expression. Migration 45 listed only U+00A0, so
-- "Scissor lift" typed with a narrow no-break space was one name on the phone
-- and two names on the server. A generated column cannot change in place, so it
-- is dropped and added again, after its row rule and the unique constraint
-- that use it. It ends up as the last column, after entry_label_key. Any
-- index on it goes with the column; the unique constraint below is the only one.
--
-- The unique constraint keeps its name and its NULLS NOT DISTINCT rule, and
-- compares entry_label_key in place of entry_label. A label of only spaces now
-- counts as no label, the same as the phone treats it.
--
-- The user_rates stream in powersync/sync-config.yaml lists its columns and
-- does not list the new one. The phone computes the key itself, so no sync
-- config change is needed.
--
-- ADD COLUMN puts the column last. The schema mirror lists both new columns
-- last too: entry_label_key, then item_name_key.
--
-- If two rows of one company already differ only by the case or spacing of
-- their label, adding the constraint fails with a unique violation naming only
-- the first clashing group. A label of only spaces clashes with a row that has
-- no label. To list every clashing group at once, run this before the deploy,
-- then merge or relabel those rows:
--   SELECT company_id, category, item_name_key, equipment_method,
--          NULLIF(lower(btrim(regexp_replace(entry_label,
--            '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085')), '')
--            AS label_key,
--          count(*), array_agg(entry_label)
--   FROM public.your_rates
--   GROUP BY 1, 2, 3, 4, 5
--   HAVING count(*) > 1;
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
--   4. Add item_name_key again with the migration 45 expression, the same way
--      as above (drop its constraints, drop the column, add it, add them back).
-- https://ripplearc.youtrack.cloud/issue/CA-1261

ALTER TABLE ONLY "public"."your_rates"
    DROP CONSTRAINT IF EXISTS "your_rates_company_category_name_method_label_key";

ALTER TABLE ONLY "public"."your_rates"
    DROP CONSTRAINT IF EXISTS "your_rates_item_name_not_blank";

ALTER TABLE "public"."your_rates"
    DROP COLUMN IF EXISTS "item_name_key";

ALTER TABLE "public"."your_rates"
    ADD COLUMN IF NOT EXISTS "entry_label_key" "text" GENERATED ALWAYS AS (NULLIF(lower(btrim(regexp_replace("entry_label", '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085')), '')) STORED;

ALTER TABLE "public"."your_rates"
    ADD COLUMN "item_name_key" "text" GENERATED ALWAYS AS (lower(btrim(regexp_replace("item_name", '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085'))) STORED NOT NULL;

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_item_name_not_blank" CHECK (length("item_name_key") > 0);

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_company_category_name_method_label_key"
    UNIQUE NULLS NOT DISTINCT ("company_id", "category", "item_name_key", "equipment_method", "entry_label_key");
