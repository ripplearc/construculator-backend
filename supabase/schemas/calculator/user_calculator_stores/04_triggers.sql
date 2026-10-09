-- Triggers for user_calculator_stores

-- The conflict rule is "the last upload to arrive wins": the server sets
-- updated_at on every UPDATE, whatever the phone sent, so the column records
-- when the server applied the write rather than what a phone's clock said.
-- INSERT keeps the phone's values; a new row has nothing to conflict with.
CREATE OR REPLACE TRIGGER "set_user_calculator_stores_updated_at"
  BEFORE UPDATE ON "public"."user_calculator_stores"
  FOR EACH ROW EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
