-- Create the check_email_exists function
-- This function runs with SECURITY DEFINER, meaning it bypasses RLS
-- and runs with the privileges of the function creator (postgres user)
CREATE OR REPLACE FUNCTION public.check_email_exists(email_input TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM "users" 
    WHERE email = email_input
  );
END;
$$;


-- Add a comment explaining the function
COMMENT ON FUNCTION public.check_email_exists(TEXT) IS 
'Securely checks if an email exists in the users table without exposing email data. Bypasses RLS for validation purposes only.';
