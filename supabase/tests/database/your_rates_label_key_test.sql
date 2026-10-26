BEGIN;

-- Tests for CA-1261: your_rates.entry_label_key, the label the way other saves
-- are matched against it. Two labels that differ only by capital letters or
-- extra spaces have one key, so the collision constraint treats them as one
-- label, the same as the phone does. Run as postgres, which bypasses RLS and
-- isolates the constraint layer.

SELECT plan(24);

INSERT INTO companies (id, email, phone, name)
VALUES ('99999999-9999-9999-9999-999999999999', 'label-key-company@example.com', '+1-555-0009', 'Label Key Test Company');

-- ============================================================
-- Shape
-- ============================================================

SELECT has_column('public', 'your_rates', 'entry_label_key', 'your_rates has an entry_label_key column');

SELECT is(
  (SELECT attgenerated::text FROM pg_attribute
     WHERE attrelid = 'public.your_rates'::regclass AND attname = 'entry_label_key'),
  's',
  'entry_label_key is a stored generated column'
);

SELECT ok(
  (SELECT pg_get_constraintdef(oid) LIKE '%entry_label_key%' AND pg_get_constraintdef(oid) NOT LIKE '%, entry_label)%'
     FROM pg_constraint
     WHERE conname = 'your_rates_company_category_name_method_label_key'
       AND conrelid = 'public.your_rates'::regclass),
  'The collision constraint compares entry_label_key and no longer entry_label'
);

SELECT is(
  (SELECT indnullsnotdistinct FROM pg_index
     WHERE indexrelid = 'public.your_rates_company_category_name_method_label_key'::regclass),
  true,
  'The collision constraint still treats NULLs as equal'
);

-- ============================================================
-- The key
-- ============================================================

INSERT INTO public.your_rates (id, company_id, category, item_name, rate_amount, rate_currency, saved_at, entry_label)
VALUES
  ('a0000000-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 1', 1.0000, 'USD', now(), E'  With \t Operator  '),
  ('a0000000-0000-0000-0000-000000000002', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 2', 1.0000, 'USD', now(), E'35 ton'),
  ('a0000000-0000-0000-0000-000000000003', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 3', 1.0000, 'USD', now(), '   '),
  ('a0000000-0000-0000-0000-000000000004', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 4', 1.0000, 'USD', now(), ''),
  ('a0000000-0000-0000-0000-000000000005', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 5', 1.0000, 'USD', now(), NULL),
  ('a0000000-0000-0000-0000-000000000006', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 6', 1.0000, 'USD', now(), 'Élévateur'),
  ('a0000000-0000-0000-0000-000000000007', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 7', 1.0000, 'USD', now(), E'After 5\u202fPM'),
  ('a0000000-0000-0000-0000-000000000008', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 8', 1.0000, 'USD', now(), E'After 5\u2007PM'),
  ('a0000000-0000-0000-0000-000000000009', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 9', 1.0000, 'USD', now(), E'\ufeffAfter 5 PM'),
  ('a0000000-0000-0000-0000-00000000000a', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 10', 1.0000, 'USD', now(), E'\u0085After 5 PM\u0085'),
  ('a0000000-0000-0000-0000-00000000000b', '99999999-9999-9999-9999-999999999999', 'material', 'Key probe 11', 1.0000, 'USD', now(), E'\u0085');

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000001'),
  'with operator',
  'The key is lower case with runs of whitespace collapsed and the ends trimmed'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000002'),
  '35 ton',
  'A non-breaking space counts as a space'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000003'),
  NULL,
  'A label of only spaces has no key'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000004'),
  NULL,
  'An empty label has no key'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000005'),
  NULL,
  'A NULL label has no key'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000006'),
  'élévateur',
  'An accented capital letter is lower-cased too'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000007'),
  'after 5 pm',
  'A narrow no-break space (U+202F) counts as a space'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000008'),
  'after 5 pm',
  'A figure space (U+2007) counts as a space'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000009'),
  'after 5 pm',
  'A byte-order mark (U+FEFF) at the start is trimmed'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-00000000000a'),
  'after 5 pm',
  'A next-line character (U+0085) at both ends is trimmed'
);

SELECT is(
  (SELECT entry_label_key FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-00000000000b'),
  NULL,
  'A label of only U+0085 has no key'
);

SELECT is(
  (SELECT entry_label FROM public.your_rates WHERE id = 'a0000000-0000-0000-0000-000000000001'),
  E'  With \t Operator  ',
  'entry_label keeps the text as it was written'
);

-- ============================================================
-- Collisions
-- ============================================================

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, unit, equipment_method, saved_at, entry_label)
VALUES ('99999999-9999-9999-9999-999999999999', 'equipment', 'Mini excavator', 145.0000, 'USD', 'day', 'day', now(), 'With operator');

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, unit, equipment_method, saved_at, entry_label)
    VALUES ('99999999-9999-9999-9999-999999999999', 'equipment', 'Mini excavator', 150.0000, 'USD', 'day', 'day', now(), 'with operator')$$,
  '23505',
  NULL,
  'A label that differs only by capital letters is the same label'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, unit, equipment_method, saved_at, entry_label)
    VALUES ('99999999-9999-9999-9999-999999999999', 'equipment', 'Mini excavator', 150.0000, 'USD', 'day', 'day', now(), '  WITH   Operator ')$$,
  '23505',
  NULL,
  'A label that differs only by extra spaces is the same label'
);

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, unit, equipment_method, saved_at, entry_label)
    VALUES ('99999999-9999-9999-9999-999999999999', 'equipment', 'Mini excavator', 150.0000, 'USD', 'day', 'day', now(), E'With\u202foperator')$$,
  '23505',
  NULL,
  'A label with a narrow no-break space is the same label as one with a normal space'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, unit, equipment_method, saved_at, entry_label)
    VALUES ('99999999-9999-9999-9999-999999999999', 'equipment', 'Mini excavator', 150.0000, 'USD', 'day', 'day', now(), 'Without operator')$$,
  'A different label is a new row'
);

INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at)
VALUES ('99999999-9999-9999-9999-999999999999', 'material', 'Rebar', 12.0000, 'USD', now());

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, entry_label)
    VALUES ('99999999-9999-9999-9999-999999999999', 'material', 'Rebar', 13.0000, 'USD', now(), '   ')$$,
  '23505',
  NULL,
  'A label of only spaces counts as no label and collides with an unlabeled row'
);

SELECT lives_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, unit, equipment_method, saved_at, entry_label)
    VALUES ('99999999-9999-9999-9999-999999999999', 'equipment', 'Mini excavator', 160.0000, 'USD', 'day', 'day', now(), 'WITH  operator')
    ON CONFLICT (company_id, category, item_name_key, equipment_method, entry_label_key)
    DO UPDATE SET rate_amount = EXCLUDED.rate_amount$$,
  'An upsert on the key columns with the same label in other capital letters updates the row'
);

SELECT is(
  (SELECT count(*) FROM public.your_rates
     WHERE company_id = '99999999-9999-9999-9999-999999999999' AND item_name = 'Mini excavator'),
  2::bigint,
  'The upsert left two rows, not three'
);

-- ============================================================
-- Never written by a client
-- ============================================================

SELECT throws_ok(
  $$INSERT INTO public.your_rates (company_id, category, item_name, rate_amount, rate_currency, saved_at, entry_label_key)
    VALUES ('99999999-9999-9999-9999-999999999999', 'material', 'Written key', 1.0000, 'USD', now(), 'x')$$,
  '428C9',
  NULL,
  'entry_label_key cannot be written'
);

SELECT * FROM finish();
ROLLBACK;
