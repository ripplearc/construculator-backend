-- Policy: owners (authenticated) may SELECT/INSERT/UPDATE/DELETE their own row
CREATE POLICY "users_owner_full_access" ON "users"
  FOR ALL
  TO authenticated
  USING (auth.uid() = credential_id)
  WITH CHECK (auth.uid() = credential_id);

-- Grant minimal SELECT columns to authenticated for general listing
GRANT SELECT ON "user_profiles" TO authenticated;
