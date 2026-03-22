-- Companies Triggers

-- Update Timestamp
-- Automatically updates updated_at column on row modification
CREATE OR REPLACE TRIGGER "trigger_update_companies_updated_at"
    BEFORE UPDATE ON "public"."companies"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
