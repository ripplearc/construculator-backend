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
-- The incoming time is also checked, on insert and on update, because the
-- phones' clocks are not trusted. A time more than 1 day after the server's
-- now() is stored as now() instead, so a phone with a clock set far ahead
-- cannot make a rate show as just used until that date has passed. An
-- infinite time ('infinity' or '-infinity') is refused with an error. The app
-- cannot send one, so only a direct API call can.
--
-- On update the stored time is then compared as above. An upsert that lands
-- on an existing row takes the update path, so it is covered too. An insert
-- has no old value, so it only gets the checks on the incoming time.
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
  IF NEW.last_used_at IN ('infinity', '-infinity') THEN
    RAISE EXCEPTION 'last_used_at must be a finite time' USING ERRCODE = '22023';
  END IF;
  IF NEW.last_used_at > now() + interval '1 day' THEN
    NEW.last_used_at := now();
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.last_used_at := GREATEST(OLD.last_used_at, NEW.last_used_at);
  END IF;
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."keep_later_your_rates_last_used_at"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."keep_later_your_rates_last_used_at"() IS 'Trigger function for your_rates. On insert and update, stores now() for a last_used_at more than 1 day ahead and refuses an infinite time. On update, keeps the later of the stored and the incoming last_used_at, so an upload of an older use from an offline phone cannot move the value back. NULL never replaces a stored time.';

CREATE OR REPLACE TRIGGER "trigger_keep_later_your_rates_last_used_at"
    BEFORE INSERT OR UPDATE ON "public"."your_rates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."keep_later_your_rates_last_used_at"();
