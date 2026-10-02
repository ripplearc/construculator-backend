-- Your Rates RLS Policies
--
-- Scoped per company (Decision 37), via the jwt_user_is_company_member()
-- helper (supabase/schemas/_shared/01_functions.sql). Any membership, any
-- role -- the ticket doesn't gate "Your rates" access by role.

ALTER TABLE "public"."your_rates" ENABLE ROW LEVEL SECURITY;


-- SELECT Policy
-- A company member can view their company's saved rates.

CREATE POLICY "your_rates_select_policy" ON "public"."your_rates"
    FOR SELECT
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"));


-- INSERT Policy
-- A company member can save a rate for their own company.

CREATE POLICY "your_rates_insert_policy" ON "public"."your_rates"
    FOR INSERT
    TO "authenticated"
    WITH CHECK ("public"."jwt_user_is_company_member"("company_id"));


-- UPDATE Policy
-- A company member can update their company's saved rates, and cannot
-- retarget a row to a company they don't belong to (both USING and
-- WITH CHECK, matching cost_estimates_update_policy's two-clause pattern).

CREATE POLICY "your_rates_update_policy" ON "public"."your_rates"
    FOR UPDATE
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"))
    WITH CHECK ("public"."jwt_user_is_company_member"("company_id"));


-- No DELETE policy, deliberately: neither Decision 55 nor the ticket
-- mentions deleting a saved rate. Matches user_consents' own
-- withheld-capability precedent (schemas/consent/user_consents/03_rls.sql).
