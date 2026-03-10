# JWT Project Claims Authentication

## Overview

This guide explains how to implement Supabase Custom Access Token Hooks to inject project permissions into JWT tokens. This will replace our current `user_has_project_permission(...)` approach which performs expensive per-row permission lookups.

## Current Problem

Our RLS policies and triggers currently use `user_has_project_permission(project_id, permission_key, auth.uid())`, which joins `project_members`, `users`, `role_permissions`, and `permissions` for **every single row** in a result set. This creates significant performance issues:

- SELECT queries on tables like `cost_estimates` trigger permission checks for each returned row
- UPDATE/DELETE triggers run permission validation for every affected row
- Complex queries can result in hundreds or thousands of redundant permission lookups

## Proposed Solution: JWT Claims

We will implement a Custom Access Token Hook that injects user permissions directly into the JWT token at sign-in and token refresh. The claim structure will be:

```json
{
  "app_metadata": {
    "projects": {
      "550e8400-e29b-41d4-a716-446655440000": ["add_cost_estimation", "edit_cost_estimation", "get_cost_estimations"],
      "7c9e6679-7425-40de-944b-e07fc1f90ae7": ["get_cost_estimations", "lock_cost_estimation"]
    }
  }
}
```

Each key is a `project_id` (UUID), and the value is an array of permission keys the user has for that project.

### Benefits

- **Performance**: Permission check happens once at token generation, not per-row
- **Scalability**: RLS policies read from `auth.jwt()` memory, not database queries
- **Frontend access**: Client can read user permissions from session metadata
- **Consistency**: Same permission data available to backend policies and frontend UI

## Implementation Guide

### Step 1: Create the Auth Hook Function

Create a Postgres function that Supabase Auth can invoke during token generation.

```sql
-- supabase/migrations/YYYYMMDDHHMMSS_auth_hook_project_permission_claims.sql

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  claims jsonb;
  projects_claims jsonb;
BEGIN
  claims := event->'claims';

  SELECT COALESCE(
    jsonb_object_agg(project_permissions.project_id, project_permissions.permissions),
    '{}'::jsonb
  )
  INTO projects_claims
  FROM (
    SELECT
      pm.project_id::text AS project_id,
      jsonb_agg(DISTINCT p.permission_key ORDER BY p.permission_key) AS permissions
    FROM public.project_members pm
    JOIN public.users u ON u.id = pm.user_id
    JOIN public.role_permissions rp ON rp.role_id = pm.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE u.credential_id = (event->>'user_id')::uuid
      AND pm.membership_status = 'joined'
    GROUP BY pm.project_id
  ) AS project_permissions;

  claims := jsonb_set(
    claims,
    '{app_metadata,projects}',
    projects_claims,
    true
  );

  RETURN jsonb_build_object('claims', claims);
END;
$$;

GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM authenticated, anon, public;
```

If `SECURITY DEFINER` is not used, `supabase_auth_admin` must also have read access to the tables touched by the hook, either through dedicated grants and RLS policies or by an equivalent controlled access path.

### Step 2: Create Helper Function for RLS Policies

Create a helper function that RLS policies and triggers can use to check permissions from the JWT:

```sql
-- supabase/migrations/YYYYMMDDHHMMSS_jwt_claim_helpers.sql

CREATE OR REPLACE FUNCTION public.jwt_has_project_permission(
  p_project_id uuid,
  p_permission_key text
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' -> 'projects' -> (p_project_id::text)),
    '[]'::jsonb
  ) ? p_permission_key
$$;
```

### Step 3: Configure Local Development

Add to `supabase/config.toml`:

```toml
[auth.hook.custom_access_token]
enabled = true
uri = "pg-functions://postgres/public/custom_access_token_hook"
```

The URI should match the schema from the function that is created. With the example above, the URI should be `pg-functions://postgres/public/custom_access_token_hook`.

### Step 4: Configure Production (Supabase Dashboard)

1. Go to **Authentication** > **Hooks** in Supabase Dashboard
2. Enable **Custom Access Token Hook**
3. Select the `custom_access_token_hook` function from the dropdown
4. Save configuration

### Step 5: Migrate RLS Policies

Replace `user_has_project_permission(...)` with the new JWT helper in RLS policies, keeping the existing permission keys used by this repo:

```sql
-- Before
CREATE POLICY "Users can read cost estimates for their projects"
  ON cost_estimates
  FOR SELECT
  TO authenticated
  USING (user_has_project_permission(project_id, 'get_cost_estimations', auth.uid()));

-- After
CREATE POLICY "Users can read cost estimates for their projects"
  ON cost_estimates
  FOR SELECT
  TO authenticated
  USING (jwt_has_project_permission(project_id, 'get_cost_estimations'));
```

### Step 6: Migrate Trigger Functions

Update trigger functions like `edit_cost_estimation` to use JWT claims instead of `user_has_project_permission(...)`:

```sql
-- Replace calls to user_has_project_permission(...) with jwt_has_project_permission(...)
IF NOT jwt_has_project_permission(NEW.project_id, 'edit_cost_estimation') THEN
  RAISE EXCEPTION 'User does not have permission to edit cost estimation';
END IF;
```

## Frontend Integration

### Reading Permissions from JWT

The Flutter frontend can access permissions directly from the current user session:

```dart
// Get current user
final user = _supabaseClient.auth.currentUser;

// Get permissions for a specific project
final projectId = '550e8400-e29b-41d4-a716-446655440000';
final appMetadata = user?.appMetadata ?? {};
final projects = appMetadata['projects'] as Map<String, dynamic>? ?? {};
final projectPermissions = (projects[projectId] as List<dynamic>?)?.cast<String>() ?? [];

// Check specific permission
final canEditCostEstimate = projectPermissions.contains('edit_cost_estimation');
final canLockEstimate = projectPermissions.contains('lock_cost_estimation');

```

### Helper Methods in SupabaseWrapper

Add the following methods to `SupabaseWrapperImpl` for convenient permission checking:

```dart
@override
List<String> getProjectPermissions(String projectId) {
  final user = _supabaseClient.auth.currentUser;
  if (user == null) return [];

  final appMetadata = user.appMetadata;
  final projects = appMetadata['projects'] as Map<String, dynamic>? ?? {};
  final permissions = projects[projectId] as List<dynamic>? ?? [];

  return permissions.cast<String>();
}

@override
bool hasProjectPermission(String projectId, String permissionKey) {
  return getProjectPermissions(projectId).contains(permissionKey);
}
```

### Refreshing Session After Permission Changes

**Critical**: When a user's role or project membership changes, the frontend **must** refresh the session to get updated JWT claims.

Add the following method to `SupabaseWrapperImpl`:

```dart
@override
Future<void> refreshSession() async {
  await _supabaseClient.auth.refreshSession();
}
```

Call after mutations that affect permissions:

```dart
// After updating user role or membership via RPC or admin action
await _supabaseWrapper.refreshSession();

// Now currentUser contains updated permissions
final updatedPermissions = _supabaseWrapper.getProjectPermissions(projectId);
```

### When to Refresh Session

Session refresh is needed in several scenarios:

#### 1. Explicit User Actions (Immediate Refresh Required)
When the **current user** performs actions that change their own permissions:
- User accepts a project invitation
- User changes their own role (if allowed)
- Admin explicitly changes the user's permissions while viewing their profile

#### 2. Background Changes by Others (Automatic Refresh Strategy)
When **someone else** changes the user's permissions (admin assigns new role, removes from project, etc.):

**Option A: Refresh on App Start**
Check and refresh when user opens the app

**Option B: Short JWT Expiry + Automatic Refresh**
Configure short JWT expiry (15-60 minutes) in Supabase Dashboard under Authentication → Settings. Supabase SDK automatically refreshes tokens before expiry.

#### 3. Manual Refresh Button (Optional)
For transparency, add a "Refresh Permissions" button in user settings.

### Recommended Strategy

For most apps, **combine multiple approaches**:

1. **Immediate refresh** after user's own permission-changing actions
2. **Refresh on app start** to catch changes made while app was closed
3. **Short JWT expiry** (30-60 minutes) as a safety net
4. **Optional manual refresh button** in settings for power users

This ensures permissions stay reasonably fresh without constant network requests or complex real-time infrastructure.


## Testing

### Database Tests

Simulate JWT claims in pgTAP tests using `set_config(...)`, matching the current test suite:

```sql
-- Set JWT claims
SELECT set_config('request.jwt.claims', '{
  "sub": "user-uuid-here",
  "app_metadata": {
    "projects": {
      "project-uuid-here": ["get_cost_estimations", "edit_cost_estimation"]
    }
  }
}', true);

-- Test policy allows read
SELECT * FROM cost_estimates WHERE project_id = 'project-uuid-here';

-- Test policy denies without permission
SELECT set_config('request.jwt.claims', '{
  "sub": "user-uuid-here",
  "app_metadata": {
    "projects": {}
  }
}', true);

-- Should return no rows
SELECT * FROM cost_estimates WHERE project_id = 'project-uuid-here';
```

### Manual Verification

1. Reset database: `npx supabase db reset`
2. Sign in locally and inspect JWT token (jwt.io or browser console)
3. Verify `app_metadata.projects` contains expected structure
4. Test permission changes + `refreshSession()` workflow

## Limitations & Considerations

1. **JWT Size Limits**: JWTs are typically limited to ~4KB. Users with many projects may hit this limit. Monitor and consider alternatives if needed.

2. **Permission Freshness**: Permissions only update when JWT refreshes. Clients must call `refreshSession()` explicitly, or wait for automatic token expiry (configure short expiry like 15-60 minutes).

3. **Hook Reliability**: If the hook function errors, token generation will fail. Ensure the hook function is well-tested and handles edge cases.

4. **Phased Migration**: Start with one table (`cost_estimates`) to validate performance and correctness before migrating all project-scoped tables.

## References

- [Supabase Custom Access Token Hooks Documentation](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)
- [Supabase Row Level Security Guide](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [PostgreSQL JSONB Functions](https://www.postgresql.org/docs/current/functions-json.html)
