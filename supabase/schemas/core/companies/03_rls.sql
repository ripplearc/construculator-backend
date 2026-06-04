-- Companies RLS Policies

-- TODO: [CA-711] Add permissive RLS policies for companies once
-- company-level permission helpers are confirmed.
-- https://ripplearc.youtrack.cloud/issue/CA-711
-- RLS is intentionally enabled here to enforce default-deny in the interim.

ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;
