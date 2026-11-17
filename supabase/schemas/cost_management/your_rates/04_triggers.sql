-- Your Rates Triggers

-- Update Timestamp
-- Automatically updates updated_at column on row modification
CREATE OR REPLACE TRIGGER "trigger_update_your_rates_updated_at"
    BEFORE UPDATE ON "public"."your_rates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();

-- Keep Later Last Used
-- Keeps the later last_used_at when two phones upload a use of the same rate, and
-- checks the incoming time on insert as well (CA-1345)
CREATE OR REPLACE TRIGGER "trigger_keep_later_your_rates_last_used_at"
    BEFORE INSERT OR UPDATE ON "public"."your_rates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."keep_later_your_rates_last_used_at"();
