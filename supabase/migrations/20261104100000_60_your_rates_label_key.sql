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
-- phones put U+202F in times such as "5 PM".
--
-- Capital letters: Postgres lower() lower-cases 410 letters that Dart's
-- toLowerCase() leaves alone, because they were added in newer Unicode versions
-- (Cherokee, Osage, Adlam, Georgian Mtavruli, some Latin letters). The owner
-- decided on 1 November 2026 that the database and the phone use one rule for
-- every letter. rate_key_lower() below is that rule: lower(), except that those
-- 410 letters keep their case, as on the phone. It is IMMUTABLE so the two
-- generated columns can use it. If a later Dart release lower-cases more
-- letters, the list must grow. The test in your_rates_label_key_test.sql names
-- two of the letters. The app has no test for them yet.
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
-- Two things can stop this migration. Two rows of one company that now give the
-- same name key and label key (for example "Scissor lift" with and without
-- U+202F, or two labels that differ only by case or spacing) fail with a unique
-- violation that names only the first group. A name of only U+202F, U+2007,
-- U+FEFF, U+0085 or spaces fails the row rule your_rates_item_name_not_blank.
-- A label of only spaces clashes with a row that has no label. Run this
-- before the deploy. It uses lower() because rate_key_lower() does not exist
-- before this migration, so it can miss two rows that differ only by one of
-- the 410 letters above. It lists every other clashing group and every blank
-- name at once. Merge, relabel or delete those rows, then deploy:
--   SELECT company_id, category,
--          lower(btrim(regexp_replace(item_name,
--            '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085')) AS name_key,
--          equipment_method,
--          NULLIF(lower(btrim(regexp_replace(entry_label,
--            '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085')), '')
--            AS label_key,
--          count(*), array_agg(item_name || ' / ' || coalesce(entry_label, '-'))
--   FROM public.your_rates
--   GROUP BY 1, 2, 3, 4, 5
--   HAVING count(*) > 1 OR bool_or(
--     lower(btrim(regexp_replace(item_name,
--       '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085')) = '');
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
--   5. DROP FUNCTION public.rate_key_lower(text);
-- https://ripplearc.youtrack.cloud/issue/CA-1261

CREATE OR REPLACE FUNCTION "public"."rate_key_lower"("value" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE STRICT PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
DECLARE
    -- The 410 capital letters that Postgres lower-cases and the phone's Dart
    -- toLowerCase() leaves alone (letters added in newer Unicode versions, such
    -- as Cherokee, Osage, Adlam and Georgian Mtavruli). They are swapped for
    -- private-use characters while lower() runs and swapped back, so a name
    -- or label gets the same key as on the phone.
    capitals CONSTANT "text" := U&'\037F\0524\0526\0528\052A\052C\052E\10C7\10CD\13A0\13A1\13A2\13A3\13A4\13A5\13A6\13A7\13A8\13A9\13AA\13AB\13AC\13AD\13AE\13AF\13B0\13B1\13B2\13B3\13B4\13B5\13B6\13B7\13B8\13B9\13BA\13BB\13BC\13BD\13BE\13BF\13C0\13C1\13C2\13C3\13C4\13C5\13C6\13C7\13C8\13C9\13CA\13CB\13CC\13CD\13CE\13CF\13D0\13D1\13D2\13D3\13D4\13D5\13D6\13D7\13D8\13D9\13DA\13DB\13DC\13DD\13DE\13DF\13E0\13E1\13E2\13E3\13E4\13E5\13E6\13E7\13E8\13E9\13EA\13EB\13EC\13ED\13EE\13EF\13F0\13F1\13F2\13F3\13F4\13F5\1C90\1C91\1C92\1C93\1C94\1C95\1C96\1C97\1C98\1C99\1C9A\1C9B\1C9C\1C9D\1C9E\1C9F\1CA0\1CA1\1CA2\1CA3\1CA4\1CA5\1CA6\1CA7\1CA8\1CA9\1CAA\1CAB\1CAC\1CAD\1CAE\1CAF\1CB0\1CB1\1CB2\1CB3\1CB4\1CB5\1CB6\1CB7\1CB8\1CB9\1CBA\1CBD\1CBE\1CBF\2C2F\2C70\2C7E\2C7F\2CEB\2CED\2CF2\A660\A698\A69A\A78D\A790\A792\A796\A798\A79A\A79C\A79E\A7A0\A7A2\A7A4\A7A6\A7A8\A7AA\A7AB\A7AC\A7AD\A7AE\A7B0\A7B1\A7B2\A7B3\A7B4\A7B6\A7B8\A7BA\A7BC\A7BE\A7C0\A7C2\A7C4\A7C5\A7C6\A7C7\A7C9\A7D0\A7D6\A7D8\A7F5\+0104B0\+0104B1\+0104B2\+0104B3\+0104B4\+0104B5\+0104B6\+0104B7\+0104B8\+0104B9\+0104BA\+0104BB\+0104BC\+0104BD\+0104BE\+0104BF\+0104C0\+0104C1\+0104C2\+0104C3\+0104C4\+0104C5\+0104C6\+0104C7\+0104C8\+0104C9\+0104CA\+0104CB\+0104CC\+0104CD\+0104CE\+0104CF\+0104D0\+0104D1\+0104D2\+0104D3\+010570\+010571\+010572\+010573\+010574\+010575\+010576\+010577\+010578\+010579\+01057A\+01057C\+01057D\+01057E\+01057F\+010580\+010581\+010582\+010583\+010584\+010585\+010586\+010587\+010588\+010589\+01058A\+01058C\+01058D\+01058E\+01058F\+010590\+010591\+010592\+010594\+010595\+010C80\+010C81\+010C82\+010C83\+010C84\+010C85\+010C86\+010C87\+010C88\+010C89\+010C8A\+010C8B\+010C8C\+010C8D\+010C8E\+010C8F\+010C90\+010C91\+010C92\+010C93\+010C94\+010C95\+010C96\+010C97\+010C98\+010C99\+010C9A\+010C9B\+010C9C\+010C9D\+010C9E\+010C9F\+010CA0\+010CA1\+010CA2\+010CA3\+010CA4\+010CA5\+010CA6\+010CA7\+010CA8\+010CA9\+010CAA\+010CAB\+010CAC\+010CAD\+010CAE\+010CAF\+010CB0\+010CB1\+010CB2\+0118A0\+0118A1\+0118A2\+0118A3\+0118A4\+0118A5\+0118A6\+0118A7\+0118A8\+0118A9\+0118AA\+0118AB\+0118AC\+0118AD\+0118AE\+0118AF\+0118B0\+0118B1\+0118B2\+0118B3\+0118B4\+0118B5\+0118B6\+0118B7\+0118B8\+0118B9\+0118BA\+0118BB\+0118BC\+0118BD\+0118BE\+0118BF\+016E40\+016E41\+016E42\+016E43\+016E44\+016E45\+016E46\+016E47\+016E48\+016E49\+016E4A\+016E4B\+016E4C\+016E4D\+016E4E\+016E4F\+016E50\+016E51\+016E52\+016E53\+016E54\+016E55\+016E56\+016E57\+016E58\+016E59\+016E5A\+016E5B\+016E5C\+016E5D\+016E5E\+016E5F\+01E900\+01E901\+01E902\+01E903\+01E904\+01E905\+01E906\+01E907\+01E908\+01E909\+01E90A\+01E90B\+01E90C\+01E90D\+01E90E\+01E90F\+01E910\+01E911\+01E912\+01E913\+01E914\+01E915\+01E916\+01E917\+01E918\+01E919\+01E91A\+01E91B\+01E91C\+01E91D\+01E91E\+01E91F\+01E920\+01E921';
    placeholders CONSTANT "text" := U&'\+0F0000\+0F0001\+0F0002\+0F0003\+0F0004\+0F0005\+0F0006\+0F0007\+0F0008\+0F0009\+0F000A\+0F000B\+0F000C\+0F000D\+0F000E\+0F000F\+0F0010\+0F0011\+0F0012\+0F0013\+0F0014\+0F0015\+0F0016\+0F0017\+0F0018\+0F0019\+0F001A\+0F001B\+0F001C\+0F001D\+0F001E\+0F001F\+0F0020\+0F0021\+0F0022\+0F0023\+0F0024\+0F0025\+0F0026\+0F0027\+0F0028\+0F0029\+0F002A\+0F002B\+0F002C\+0F002D\+0F002E\+0F002F\+0F0030\+0F0031\+0F0032\+0F0033\+0F0034\+0F0035\+0F0036\+0F0037\+0F0038\+0F0039\+0F003A\+0F003B\+0F003C\+0F003D\+0F003E\+0F003F\+0F0040\+0F0041\+0F0042\+0F0043\+0F0044\+0F0045\+0F0046\+0F0047\+0F0048\+0F0049\+0F004A\+0F004B\+0F004C\+0F004D\+0F004E\+0F004F\+0F0050\+0F0051\+0F0052\+0F0053\+0F0054\+0F0055\+0F0056\+0F0057\+0F0058\+0F0059\+0F005A\+0F005B\+0F005C\+0F005D\+0F005E\+0F005F\+0F0060\+0F0061\+0F0062\+0F0063\+0F0064\+0F0065\+0F0066\+0F0067\+0F0068\+0F0069\+0F006A\+0F006B\+0F006C\+0F006D\+0F006E\+0F006F\+0F0070\+0F0071\+0F0072\+0F0073\+0F0074\+0F0075\+0F0076\+0F0077\+0F0078\+0F0079\+0F007A\+0F007B\+0F007C\+0F007D\+0F007E\+0F007F\+0F0080\+0F0081\+0F0082\+0F0083\+0F0084\+0F0085\+0F0086\+0F0087\+0F0088\+0F0089\+0F008A\+0F008B\+0F008C\+0F008D\+0F008E\+0F008F\+0F0090\+0F0091\+0F0092\+0F0093\+0F0094\+0F0095\+0F0096\+0F0097\+0F0098\+0F0099\+0F009A\+0F009B\+0F009C\+0F009D\+0F009E\+0F009F\+0F00A0\+0F00A1\+0F00A2\+0F00A3\+0F00A4\+0F00A5\+0F00A6\+0F00A7\+0F00A8\+0F00A9\+0F00AA\+0F00AB\+0F00AC\+0F00AD\+0F00AE\+0F00AF\+0F00B0\+0F00B1\+0F00B2\+0F00B3\+0F00B4\+0F00B5\+0F00B6\+0F00B7\+0F00B8\+0F00B9\+0F00BA\+0F00BB\+0F00BC\+0F00BD\+0F00BE\+0F00BF\+0F00C0\+0F00C1\+0F00C2\+0F00C3\+0F00C4\+0F00C5\+0F00C6\+0F00C7\+0F00C8\+0F00C9\+0F00CA\+0F00CB\+0F00CC\+0F00CD\+0F00CE\+0F00CF\+0F00D0\+0F00D1\+0F00D2\+0F00D3\+0F00D4\+0F00D5\+0F00D6\+0F00D7\+0F00D8\+0F00D9\+0F00DA\+0F00DB\+0F00DC\+0F00DD\+0F00DE\+0F00DF\+0F00E0\+0F00E1\+0F00E2\+0F00E3\+0F00E4\+0F00E5\+0F00E6\+0F00E7\+0F00E8\+0F00E9\+0F00EA\+0F00EB\+0F00EC\+0F00ED\+0F00EE\+0F00EF\+0F00F0\+0F00F1\+0F00F2\+0F00F3\+0F00F4\+0F00F5\+0F00F6\+0F00F7\+0F00F8\+0F00F9\+0F00FA\+0F00FB\+0F00FC\+0F00FD\+0F00FE\+0F00FF\+0F0100\+0F0101\+0F0102\+0F0103\+0F0104\+0F0105\+0F0106\+0F0107\+0F0108\+0F0109\+0F010A\+0F010B\+0F010C\+0F010D\+0F010E\+0F010F\+0F0110\+0F0111\+0F0112\+0F0113\+0F0114\+0F0115\+0F0116\+0F0117\+0F0118\+0F0119\+0F011A\+0F011B\+0F011C\+0F011D\+0F011E\+0F011F\+0F0120\+0F0121\+0F0122\+0F0123\+0F0124\+0F0125\+0F0126\+0F0127\+0F0128\+0F0129\+0F012A\+0F012B\+0F012C\+0F012D\+0F012E\+0F012F\+0F0130\+0F0131\+0F0132\+0F0133\+0F0134\+0F0135\+0F0136\+0F0137\+0F0138\+0F0139\+0F013A\+0F013B\+0F013C\+0F013D\+0F013E\+0F013F\+0F0140\+0F0141\+0F0142\+0F0143\+0F0144\+0F0145\+0F0146\+0F0147\+0F0148\+0F0149\+0F014A\+0F014B\+0F014C\+0F014D\+0F014E\+0F014F\+0F0150\+0F0151\+0F0152\+0F0153\+0F0154\+0F0155\+0F0156\+0F0157\+0F0158\+0F0159\+0F015A\+0F015B\+0F015C\+0F015D\+0F015E\+0F015F\+0F0160\+0F0161\+0F0162\+0F0163\+0F0164\+0F0165\+0F0166\+0F0167\+0F0168\+0F0169\+0F016A\+0F016B\+0F016C\+0F016D\+0F016E\+0F016F\+0F0170\+0F0171\+0F0172\+0F0173\+0F0174\+0F0175\+0F0176\+0F0177\+0F0178\+0F0179\+0F017A\+0F017B\+0F017C\+0F017D\+0F017E\+0F017F\+0F0180\+0F0181\+0F0182\+0F0183\+0F0184\+0F0185\+0F0186\+0F0187\+0F0188\+0F0189\+0F018A\+0F018B\+0F018C\+0F018D\+0F018E\+0F018F\+0F0190\+0F0191\+0F0192\+0F0193\+0F0194\+0F0195\+0F0196\+0F0197\+0F0198\+0F0199';
BEGIN
    RETURN translate(lower(translate("value", capitals, placeholders)), placeholders, capitals);
END
$$;

ALTER TABLE ONLY "public"."your_rates"
    DROP CONSTRAINT IF EXISTS "your_rates_company_category_name_method_label_key";

ALTER TABLE ONLY "public"."your_rates"
    DROP CONSTRAINT IF EXISTS "your_rates_item_name_not_blank";

ALTER TABLE "public"."your_rates"
    DROP COLUMN IF EXISTS "item_name_key";

ALTER TABLE "public"."your_rates"
    ADD COLUMN IF NOT EXISTS "entry_label_key" "text" GENERATED ALWAYS AS (NULLIF(public.rate_key_lower(btrim(regexp_replace("entry_label", '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085')), '')) STORED;

ALTER TABLE "public"."your_rates"
    ADD COLUMN "item_name_key" "text" GENERATED ALWAYS AS (public.rate_key_lower(btrim(regexp_replace("item_name", '[\s\u00a0\u2007\u202f\ufeff]+', ' ', 'g'), U&' \0085'))) STORED NOT NULL;

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_item_name_not_blank" CHECK (length("item_name_key") > 0);

ALTER TABLE ONLY "public"."your_rates"
    ADD CONSTRAINT "your_rates_company_category_name_method_label_key"
    UNIQUE NULLS NOT DISTINCT ("company_id", "category", "item_name_key", "equipment_method", "entry_label_key");
