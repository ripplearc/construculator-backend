-- Add country_code column to users table for storing country codes
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS country_code TEXT;
