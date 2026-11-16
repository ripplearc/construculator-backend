-- CA-1345: Keep the later your_rates.last_used_at when two phones upload a use
-- of the same saved rate.
--
-- The phone stamps last_used_at itself when a rate is added to an estimate
-- (CA-1266), and the upload queue can hold that change for days. Without this
-- rule the server stores whichever upload arrives last: phone A uploads
-- Monday's use after phone B uploaded Tuesday's, and both phones then show
-- the rate as used on Monday. The storyboard (CUJ 6, "Used label") counts from
-- "the last time this rate was added to any estimate", so the later time wins.
--
-- GREATEST ignores NULL, so one expression covers every case:
--   old NULL, new set    -> new (the first use)
--   old set, new earlier -> old
--   old set, new later   -> new
--   old set, new NULL    -> old (a full-row upload from a phone that has not
--                           seen the use must not erase it)
--   both NULL            -> NULL
-- Nothing else in the row is touched, so a price or label sent in the same
-- update is still applied. The rule applies to every role, not only to
-- authenticated: a manual correction that moves the value back has to disable
-- the trigger first.
--
-- It fires on UPDATE only. An insert has no old value, and an upsert that
-- lands on an existing row takes the update path, so it is covered too.
--
-- Times are the phones' own clocks. A phone with a clock set far ahead stamps a
-- time that no later real use can replace, so that rate keeps showing as just
-- used until someone disables the trigger and corrects the row. This rule does
-- not try to prevent that.
--
-- This is the one exception to the storyboard's general rule for two phones
-- changing the same saved rate ("the change the server receives last wins"),
-- which still holds for every other column.
--
-- No app change and no sync-config change. The user_rates stream sends the
-- stored time, so every phone is shown the later one.
--
-- Mirrors supabase/schemas/cost_management/your_rates/03_functions.sql and
-- 04_triggers.sql, keep them in step.
--
-- Rollback (manual, Supabase migrations are append-only):
--   DROP TRIGGER trigger_keep_later_your_rates_last_used_at ON public.your_rates;
--   DROP FUNCTION public.keep_later_your_rates_last_used_at();
-- https://ripplearc.youtrack.cloud/issue/CA-1345

CREATE OR REPLACE FUNCTION "public"."keep_later_your_rates_last_used_at"()
    RETURNS TRIGGER
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.last_used_at := GREATEST(OLD.last_used_at, NEW.last_used_at);
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."keep_later_your_rates_last_used_at"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."keep_later_your_rates_last_used_at"() IS 'Trigger function for your_rates. Keeps the later of the stored and the incoming last_used_at, so an upload of an older use from an offline phone cannot move the value back. NULL never replaces a stored time.';

CREATE OR REPLACE TRIGGER "trigger_keep_later_your_rates_last_used_at"
    BEFORE UPDATE ON "public"."your_rates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."keep_later_your_rates_last_used_at"();
