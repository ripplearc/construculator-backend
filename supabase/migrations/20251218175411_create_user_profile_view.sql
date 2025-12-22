-- Create a public profiles view
CREATE OR REPLACE VIEW "user_profiles" AS
SELECT 
  id,
  credential_id,
  first_name,
  last_name,
  professional_role,
  profile_photo_url
FROM "users";
