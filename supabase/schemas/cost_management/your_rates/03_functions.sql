-- Your Rates Functions

-- Keep Later Last Used
-- Keeps the later of the stored and the incoming last_used_at (CA-1345)
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
