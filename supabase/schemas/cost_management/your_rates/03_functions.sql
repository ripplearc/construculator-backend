-- Your Rates Functions

-- Keep Later Last Used
-- Keeps the later of the stored and the incoming last_used_at, caps a time more
-- than 1 day ahead at now() and refuses an infinite one (CA-1345)
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
