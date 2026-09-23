-- Your Rates Triggers

-- Update Timestamp
-- Automatically updates updated_at column on row modification
CREATE OR REPLACE TRIGGER "trigger_update_your_rates_updated_at"
    BEFORE UPDATE ON "public"."your_rates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
