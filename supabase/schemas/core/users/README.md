# Users Module

## Overview

The `users` table stores core user profile information and links to Supabase Auth through the `credential_id`. This is the primary user entity in the system, referenced by most other tables.

## Table Structure

### Core Fields
- `id` - UUID primary key (internal user ID)
- `credential_id` - UUID linking to auth.users (Supabase Auth)
- `email` - User's email (unique)
- `phone` - Optional phone number (unique if provided)
- `first_name` - User's first name
- `last_name` - User's last name
- `professional_role` - Foreign key to professional_roles table
- `profile_photo_url` - URL to profile photo
- `country_code` - Country code (e.g., 'US', 'CA')

### Status & Preferences
- `user_status` - Enum: 'active' or 'inactive'
- `user_preferences` - JSONB field for user settings

### Metadata
- `created_at` - Account creation timestamp
- `updated_at` - Last update timestamp (auto-updated via trigger)

## Business Rules

### 1. Auth Integration
- `credential_id` links to Supabase Auth's `auth.users.id`
- This is the **bridge** between authentication and application data
- One-to-one relationship: one auth user = one profile user
- `credential_id` is unique and required

### 2. Email & Phone Uniqueness
- Email must be unique across all users
- Phone must be unique if provided (can be NULL)
- These constraints prevent duplicate accounts

### 3. User Status
Two statuses available:
- **active**: User can access the system
- **inactive**: User is disabled/suspended

Inactive users:
- Cannot log in (should be checked in auth layer)
- Retain all data
- Can be reactivated

### 4. User Preferences
The `user_preferences` JSONB field stores personalized settings:
- UI preferences (theme, language)
- Notification settings
- Display preferences
- Feature flags
- Custom configurations

Example structure:
```json
{
  "theme": "dark",
  "language": "en",
  "notifications": {
    "email": true,
    "push": false
  },
  "default_currency": "USD"
}
```

### 5. Professional Role
- Required field linking to `professional_roles` table
- Examples: "General Contractor", "Architect", "Project Manager"
- Determines user's profession/specialization
- Used for display and filtering

## Functions

### `check_email_exists(email_input)`
**Purpose**: Securely check if an email is already registered

**Security**:
- `SECURITY DEFINER` - runs with elevated privileges
- Bypasses RLS to check all emails
- Returns only boolean (doesn't expose email data)

**Use Case**:
- Email validation during signup
- Check availability before account creation

**Example**:
```sql
SELECT check_email_exists('user@example.com');
-- Returns: true or false
```

## Triggers

### `trigger_update_users_updated_at`
**Purpose**: Automatically timestamps row modifications.
- Listens to `BEFORE UPDATE` on `users` table
- Executes shared `set_current_timestamp_updated_at()` function
- Guarantees `updated_at` matches the exact time of the change

## Views

### `user_profiles`
**Purpose**: Public subset of user data for display

**Columns Exposed**:
- `id`
- `credential_id`
- `first_name`
- `last_name`
- `professional_role`
- `profile_photo_url`

**Hidden Columns**:
- Email (private)
- Phone (private)
- User preferences (private)
- Status (internal)

**Use Case**: Displaying user info in lists, comments, assignments without exposing sensitive data.

## Indexes

Performance indexes for common queries:
- `users_credential_id_key` - Unique constraint (auth lookup)
- `users_email_key` - Unique constraint (email lookup)
- `users_phone_key` - Unique constraint (phone lookup)
- `users_professional_role_idx` - Filter by role
- `users_user_status_idx` - Filter by status
- `users_created_at_idx` - Sort by registration date
- `idx_users_credential_id` - Fast auth lookups
- `idx_users_id_credential` - Composite index for joins

## RLS Policies

### Owner Full Access Policy
**Name**: `users_owner_full_access`

**Applies to**: Authenticated users

**Access**: SELECT, INSERT, UPDATE, DELETE

**Rule**: Users can only access their own profile
```sql
auth.uid() = credential_id
```

**Behavior**:
- Users see only their own row
- Users can update only their own data
- No access to other users' profiles (unless additional policies exist)

**Note**: For viewing other users (e.g., in project teams), use the `user_profiles` view or add specific permissive policies.

## Usage Examples

### Creating a New User Profile
```sql
-- After user signs up via auth, create profile
INSERT INTO users (
  credential_id,
  email,
  first_name,
  last_name,
  professional_role,
  user_preferences
) VALUES (
  auth.uid(),  -- Links to authenticated user
  'user@example.com',
  'John',
  'Doe',
  (SELECT id FROM professional_roles WHERE name = 'General Contractor'),
  '{"theme": "light", "language": "en"}'::jsonb
);
```

### Updating User Profile
```sql
UPDATE users
SET
  first_name = 'Jane',
  last_name = 'Smith',
  profile_photo_url = 'https://storage.example.com/photos/user.jpg'
  -- updated_at is handled automatically by trigger
WHERE credential_id = auth.uid();
```

### Updating User Preferences
```sql
-- Merge new preferences with existing
UPDATE users
SET user_preferences = user_preferences || '{"theme": "dark"}'::jsonb
WHERE credential_id = auth.uid();

-- Or completely replace
UPDATE users
SET user_preferences = '{"theme": "dark", "language": "es"}'::jsonb
WHERE credential_id = auth.uid();
```

### Checking Email Availability
```sql
-- Before signup
SELECT check_email_exists('newuser@example.com') AS email_taken;

-- If false, email is available
```

### Deactivating a User
```sql
UPDATE users
SET user_status = 'inactive'
WHERE id = 'user-uuid';

-- Reactivate
UPDATE users
SET user_status = 'active'
WHERE id = 'user-uuid';
```

### Getting User by Auth ID
```sql
SELECT *
FROM users
WHERE credential_id = auth.uid();
```

### Getting Public Profile
```sql
-- Use view to get safe public data
SELECT *
FROM user_profiles
WHERE id = 'user-uuid';
```

## Related Tables

### Direct References
- `professional_roles` - User's profession

### Tables Referencing Users
- `cost_estimates` - creator_user_id, locked_by_user_id
- `cost_items` - (via cost_estimates)
- `cost_estimate_logs` - user_id
- `cost_files` - uploaded_by_user_id
- `projects` - creator_user_id
- `project_members` - user_id, invited_by_user_id
- `company_users` - user_id
- `team_members` - member_id
- `teams` - created_by_user_id
- `comments` - author_user_id
- `comment_mentions` - mentioned_user_id
- `notifications` - recipient_user_id, triggering_user_id
- `task_assignments` - assignee_user_id, assigned_by_user_id
- `user_favorites` - user_id

## Best Practices

### Profile Creation
- Always create user profile immediately after auth signup
- Use database triggers or application logic
- Ensure `credential_id` matches `auth.uid()`

### Email Validation
- Check existence before account creation
- Use `check_email_exists()` function
- Handle case-insensitivity in application layer

### Privacy
- Use `user_profiles` view for public display
- Don't expose email/phone in public APIs
- Respect user preferences for visibility

### Preferences Management
- Use JSONB operators for partial updates
- Validate preference schema in application
- Provide sensible defaults
- Document preference structure

### Status Management
- Inactive users should be blocked at auth layer
- Consider "soft delete" via status instead of deletion
- Retain data for audit/recovery purposes

## Testing

See test files:
- `supabase/tests/functions/check_email_exists_test.sql`

## Migration Notes

- `credential_id` was introduced to link auth.users
- `country_code` added in migration `20251127064917_add_country_code_to_users.sql`
- RLS policies added in migration `20251218175536_RLS_07_users_table_rules.sql`
- View created in migration `20251218175411_create_user_profile_view.sql`
