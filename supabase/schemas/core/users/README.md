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
- Enforced by a foreign key (`users_credential_id_fkey`, `ON DELETE CASCADE`) — a `users` row can no longer point at a nonexistent `auth.users` id, and deleting the auth account removes the profile with it

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

### `get_my_company_id()`
**Purpose**: Returns the signed-in caller's own company id, or `NULL` if the caller has none.

**Security**:
- `SECURITY DEFINER`, `search_path` set to `public`
- Finds the caller through `auth.uid()`, `users.credential_id`, `users.id` and `company_users`
- Does not use the `internal_user_id` token claim, so it works straight after sign-up
- `EXECUTE` is revoked from `PUBLIC` and `anon`, and granted to `authenticated`
- Needed because `company_users` has RLS on and no policies

**Example**:
```sql
SELECT get_my_company_id();
```

### `ensure_my_company()`
**Purpose**: Returns the signed-in caller's company id, creating a personal company first if the caller has none. The app calls it at sign-in (CA-1262), which repairs an account that has a profile but no company.

**Behavior**:
- Safe to call twice: the second call returns the same company. The caller's `users` row is locked (`FOR UPDATE`) so two calls at the same time wait for each other
- Returns `NULL`, and creates nothing, if the caller has no `users` row yet
- Creates the company through `create_personal_company()`, the same function the trigger below uses, so the name, placeholder email and phone and Admin row are the same
- If the caller already has several companies, returns the oldest, like `get_my_company_id()`

**Security**:
- `SECURITY DEFINER`, `search_path` set to `public`
- `EXECUTE` is revoked from `PUBLIC` and `anon`, and granted to `authenticated`

**Example**:
```sql
SELECT ensure_my_company();
```

### `create_personal_company(user_id, first_name)`
**Purpose**: Creates one `companies` row and one Admin `company_users` row for the given user, and returns the company id. Called by the trigger below and by `ensure_my_company()`.
- `SECURITY DEFINER`, `search_path` set to `public`. `EXECUTE` is revoked from `PUBLIC`, `anon` and `authenticated`

## Triggers

### `trigger_update_users_updated_at`
**Purpose**: Automatically timestamps row modifications.
- Listens to `BEFORE UPDATE` on `users` table
- Executes shared `set_current_timestamp_updated_at()` function
- Guarantees `updated_at` matches the exact time of the change

### `trigger_create_personal_company`
**Purpose**: Gives every new user one personal company.
- Listens to `AFTER INSERT` on `users` table
- Executes `create_personal_company_for_new_user()`, which calls `create_personal_company()`
- Otherwise creates one `companies` row and one Admin `company_users` row
- Company name is `first_name` plus "'s company". A first name that is empty or only spaces, tabs, new lines or no-break/zero-width spaces gives "My company". Duplicate names are accepted
- Company email is `hidden-<company_id>@internal.construculator.app` and phone is `hidden-<company_id>`. These are placeholders for the required columns
- If any step fails, the whole `users` insert rolls back
- The function is `SECURITY DEFINER` with `search_path` set to `public`. Clients cannot execute it
- The `Admin` row in `roles` must exist, or the insert fails. Migration `20261004120000_48_personal_company_trigger.sql` creates it, with the same id, level and description as the seeder
- `Admin` is a project role (`context_type = 'project'`). It is reused on purpose for company membership and found by `role_name`. A separate company role would need a change to the trigger

### `trigger_delete_empty_company`
**Purpose**: Lets a user be deleted even though the trigger above gave them a company.
- Listens to `AFTER DELETE` on `company_users` table
- Executes `delete_company_when_last_member_leaves()`
- Deletes the company when no `company_users` row is left, unless any row still points at it (a project, a team, `your_rates`, or any later table). The delete is tried and a foreign key refusal is caught, so no list of tables has to be kept
- Locks the company row first (`FOR UPDATE`), so two sessions leaving or joining at once wait for each other
- `company_users.user_id` is `ON DELETE CASCADE`, so deleting a `users` row (or the `auth.users` account, which cascades to `users`) removes the membership first
- The function is `SECURITY DEFINER` with `search_path` set to `public`. Clients cannot execute it

## Views

### `user_profiles`
**Purpose**: Public subset of user data for display

**Columns Exposed**:
- `id`
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

## RLS Policies

### Select Policy
**Name**: `users_select_own`

**Applies to**: Authenticated users

**Access**: SELECT

**Rule**: Users can read only their own profile
```sql
auth.uid() = credential_id
```

### Update Policy
**Name**: `users_update_own`

**Applies to**: Authenticated users

**Access**: UPDATE

**Rule**: Users can update only their own profile
```sql
auth.uid() = credential_id
```

### Owner Policy
**Name**: `users_owner_full_access` (migration `20251218175536_RLS_07_users_table_rules.sql`)

**Applies to**: Authenticated users

**Access**: ALL (select, insert, update, delete)

**Rule**: Users can act only on their own row. Both the read check and the write check are:
```sql
auth.uid() = credential_id
```

**Note**: The app inserts the profile row itself during account creation, and this policy allows it. No trigger on `auth.users` creates the profile. Cross-user reads (e.g., viewing teammates) via `user_profiles` are deferred. The owner policy means the view only returns the caller's own row under `SECURITY INVOKER`. A separate policy will be introduced when team-based access is implemented.

A user can delete their own row. The `company_users` row goes with it, and the personal company is removed if no one else is a member and no project or team uses it (see `trigger_delete_empty_company`).

## Usage Examples

### Creating a New User Profile

The app inserts the profile row itself during account creation. The `users_owner_full_access` policy allows the insert when `credential_id` matches `auth.uid()`. The `AFTER INSERT` trigger then creates the user's personal company (see Triggers).

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
- The app inserts the profile row itself. The insert is allowed only when `credential_id` matches `auth.uid()`
- The `AFTER INSERT` trigger on `users` creates the personal company in the same transaction

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
- `supabase/tests/database/personal_company_trigger_test.sql`
- `supabase/tests/database/ensure_my_company_test.sql`

## Migration Notes

- `credential_id` was introduced to link auth.users
- `credential_id -> auth.users(id)` FK (`ON DELETE CASCADE`) added under CA-995, closing the gap where a hand-inserted `users` row could point at a nonexistent auth account
- `country_code` added in migration `20251127064917_add_country_code_to_users.sql`
- RLS policies added in migration `20251218175536_RLS_07_users_table_rules.sql`
- Personal company trigger, `get_my_company_id()`, `ON DELETE CASCADE` on `company_users.user_id` and the empty company trigger added in migration `20261004120000_48_personal_company_trigger.sql`
- `ensure_my_company()` and `create_personal_company()` added in migration `20261006120000_49_ensure_my_company.sql`, which also moves the company creation out of the trigger function
- This migration has a later timestamp than the migrations in backend PRs #57 and #58. If it is pushed to a remote database first, those two need `supabase db push --include-all`
- View created in migration `20251218175411_create_user_profile_view.sql`
