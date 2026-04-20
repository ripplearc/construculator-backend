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
    "internal_user_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "projects": {
      "550e8400-e29b-41d4-a716-446655440000": ["add_cost_estimation", "edit_cost_estimation", "get_cost_estimations"],
      "7c9e6679-7425-40de-944b-e07fc1f90ae7": ["get_cost_estimations", "lock_cost_estimation"]
    }
  }
}
```

- `internal_user_id`: The internal application user ID (`users.id`), used by triggers to set fields like `locked_by_user_id` without database lookups
- `projects`: Each key is a `project_id` (UUID), and the value is an array of permission keys the user has for that project

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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claims jsonb;
  projects_claims jsonb;
  user_internal_id uuid;
BEGIN
  claims := event->'claims';

  -- Get the internal user ID (users.id) from credential_id
  SELECT u.id INTO user_internal_id
  FROM public.users u
  WHERE u.credential_id = (event->>'user_id')::uuid;

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

  -- Ensure app_metadata exists, then merge in projects and internal_user_id
  claims := jsonb_set(
    claims,
    '{app_metadata}',
    COALESCE(claims->'app_metadata', '{}'::jsonb) || jsonb_build_object(
      'projects', projects_claims,
      'internal_user_id', user_internal_id
    ),
    true
  );

  RETURN jsonb_build_object('claims', claims);
EXCEPTION WHEN OTHERS THEN
  -- Log the error and return unmodified event rather than empty claims
  RAISE WARNING 'custom_access_token_hook failed for user %: %',
    (event->>'user_id')::uuid, SQLERRM;
  -- Return original event to prevent login failures due to hook errors
  RETURN event;
END;
$$;

GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM authenticated, anon, public;
```

If you prefer not to use `SECURITY DEFINER`, then `supabase_auth_admin` needs direct read access to every table the hook touches. For this specific hook, that alternative would look like:

```sql
GRANT SELECT ON public.project_members, public.users, public.role_permissions, public.permissions TO supabase_auth_admin;
```

That grant-based approach can work, but it is broader than necessary for this use case. The recommended default for this repo is to keep the hook as `SECURITY DEFINER` and avoid granting table-level reads unless there is a specific operational reason to do so.

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

**Important**: This function is intentionally stateless and reads only from the JWT token in memory. It must never perform database queries, as that would reintroduce the performance problem this migration is solving. 

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
try {
  await _supabaseWrapper.refreshSession();

  // Now currentUser contains updated permissions
  final updatedPermissions = _supabaseWrapper.getProjectPermissions(projectId);
} on AuthException catch (e) {
  // Refresh token expired — force re-login
  await _supabaseWrapper.signOut();
  // Navigate to login screen
  // Example: Navigator.of(context).pushReplacementNamed('/login');
} catch (e) {
  // Log and handle gracefully
  print('Failed to refresh session: $e');
  // Show error message to user
}
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

Simulate JWT claims in pgTAP tests using `set_config(...)`, using test helper functions consistent with the existing test suite:

```sql
-- Use test helpers to create users and projects
SELECT tests.create_supabase_user('test_user');
SELECT tests.authenticate_as('test_user');

-- Get the actual UUID generated by the test helpers
SELECT tests.get_supabase_uid('test_user') AS user_id;

-- Assuming you have a test project created, get its ID
-- Example: SELECT id FROM projects WHERE name = 'test_project' INTO project_id;

-- Set JWT claims with actual UUIDs from test helpers
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', tests.get_supabase_uid('test_user'),
  'app_metadata', json_build_object(
    'projects', json_build_object(
      project_id::text, '["get_cost_estimations", "edit_cost_estimation"]'::jsonb
    )
  )
)::text, true);

-- Test policy allows read
SELECT * FROM cost_estimates WHERE project_id = project_id;

-- Test policy denies without permission
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', tests.get_supabase_uid('test_user'),
  'app_metadata', json_build_object(
    'projects', '{}'::jsonb
  )
)::text, true);

-- Should return no rows
SELECT * FROM cost_estimates WHERE project_id = project_id;
```

**Note**: Adapt the above examples to match the exact helper pattern your test suite uses. The key point is to avoid placeholder strings like `"user-uuid-here"` and instead use the test suite's helper functions to generate valid UUIDs.

### Manual Verification

1. Reset database: `npx supabase db reset`
2. Sign in locally and inspect JWT token (jwt.io or browser console)
3. Verify `app_metadata.projects` contains expected structure
4. Test permission changes + `refreshSession()` workflow

## Limitations & Considerations

1. **JWT Size Limits**: JWTs are typically limited to ~4KB. Users with many projects may hit this limit.

   **Monitoring Threshold**: A user in 10 projects with 8 permissions each generates approximately 3KB of claims — already close to the limit. Monitor users who are members of **more than 15 projects** as they approach the 4KB threshold.

   **Monitoring Query**: Run this periodically to identify users approaching the limit:

   ```sql
   SELECT
     u.credential_id,
     COUNT(DISTINCT pm.project_id) AS project_count,
     SUM(per_project.perm_count) AS total_permission_entries,
     SUM(per_project.perm_count) * 20 + COUNT(DISTINCT pm.project_id) * 36 AS estimated_bytes
   FROM project_members pm
   JOIN users u ON u.id = pm.user_id
   JOIN (
     SELECT pm2.user_id, pm2.project_id, COUNT(DISTINCT p2.permission_key) AS perm_count
     FROM project_members pm2
     JOIN role_permissions rp2 ON rp2.role_id = pm2.role_id
     JOIN permissions p2 ON p2.id = rp2.permission_id
     WHERE pm2.membership_status = 'joined'
     GROUP BY pm2.user_id, pm2.project_id
   ) per_project ON per_project.user_id = pm.user_id AND per_project.project_id = pm.project_id
   WHERE pm.membership_status = 'joined'
   GROUP BY u.credential_id
   HAVING estimated_bytes > 3000  -- Alert when approaching 4KB limit
   ORDER BY estimated_bytes DESC
   LIMIT 20;
   ```

   This query correctly counts permissions per-project (e.g., a user in 10 projects with 8 permissions each = 80 total entries, not 8). The `HAVING` clause can use `estimated_bytes > 3000` for a direct size-based alert or `COUNT(DISTINCT pm.project_id) > 15` for a project-count threshold.

   **Mitigation Strategy**: If users start hitting the limit, consider migrating to **scoped tokens per active project** where the JWT contains full permissions for only the currently active project. This requires the frontend to call `refreshSession()` when switching projects, but keeps tokens small regardless of total project count.

   ### Migration Plan: Scoped Token per Active Project

   Execute this migration when the monitoring query surfaces users with `estimated_bytes > 3,000`.

   #### Phase 1: Backend — Update Hook to Accept Active Project Scope

   Modify `custom_access_token_hook` to read an optional `active_project_id` from `app_metadata`. If present, emit only that project's permissions; otherwise fall back to all-projects behavior (preserving backward compatibility during rollout):

   ```sql
   CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
   RETURNS jsonb
   LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public
   AS $$
   DECLARE
     claims jsonb;
     projects_claims jsonb;
     active_project_id uuid;
   BEGIN
     claims := event->'claims';
     active_project_id := (event->'claims'->'app_metadata'->>'active_project_id')::uuid;

     SELECT COALESCE(jsonb_object_agg(pp.project_id, pp.permissions), '{}'::jsonb)
     INTO projects_claims
     FROM (
       SELECT pm.project_id::text, jsonb_agg(DISTINCT p.permission_key ORDER BY p.permission_key) AS permissions
       FROM public.project_members pm
       JOIN public.users u ON u.id = pm.user_id
       JOIN public.role_permissions rp ON rp.role_id = pm.role_id
       JOIN public.permissions p ON p.id = rp.permission_id
       WHERE u.credential_id = (event->>'user_id')::uuid
         AND pm.membership_status = 'joined'
         AND (active_project_id IS NULL OR pm.project_id = active_project_id)
       GROUP BY pm.project_id
     ) pp;

     claims := jsonb_set(claims, '{app_metadata,projects}', projects_claims, true);
     RETURN jsonb_build_object('claims', claims);
   EXCEPTION WHEN OTHERS THEN
     RAISE WARNING 'custom_access_token_hook failed for user %: %', (event->>'user_id')::uuid, SQLERRM;
     RETURN event;
   END;
   $$;
   ```

   #### Phase 2: Frontend — Wire into `CurrentProjectNotifier`

   Add `setActiveProject()` to `SupabaseWrapper`:

   ```dart
   @override
   Future<void> setActiveProject(String projectId) async {
     await _supabaseClient.auth.updateUser(
       UserAttributes(data: {'active_project_id': projectId}),
     );
     try {
       await _supabaseClient.auth.refreshSession();
     } on AuthException catch (_) {
       await _supabaseClient.auth.signOut();
     }
   }
   ```

   `CurrentProjectNotifier` is the natural integration point — call `setActiveProject()` whenever the active project changes.

   > **Note**: `updateUser` adds a network round-trip on every project switch. If that latency is unacceptable, consider a custom RPC that accepts `project_id` and returns a scoped token directly, bypassing the `updateUser` route.

   #### Phase 3: Rollout

   1. **Deploy hook change** — backward compatible; no `active_project_id` in metadata means all-projects behavior is unchanged.
   2. **Enable scoped mode for flagged users** — set `active_project_id` in `app_metadata` server-side for users identified by the monitoring query.
   3. **Enable for all new users** — set `active_project_id` at sign-up / first project join.
   4. **Migrate remaining users** — batch update existing users below the threshold.

   #### Rollback Plan

   Remove the `active_project_id` filter from the hook to revert to all-projects behavior. No data migration required.

   #### Exit Criteria

   - [ ] No users in monitoring query above `estimated_bytes > 3,000`
   - [ ] `setActiveProject()` integrated into `CurrentProjectNotifier` and unit tested
   - [ ] pgTAP tests cover: scoped token allows access to active project, denies access to non-active project
   - [ ] Rollback verified in staging

2. **Permission Freshness**: Permissions only update when JWT refreshes. Clients must call `refreshSession()` explicitly, or wait for automatic token expiry (configure short expiry like 15-60 minutes).

3. **Hook Reliability**: If the hook function errors, token generation will fail. Ensure the hook function is well-tested and handles edge cases.

4. **Phased Migration**: Start with one table (`cost_estimates`) to validate performance and correctness before migrating all project-scoped tables.

   **Phase 1 Exit Criteria (cost_estimates)**:
   - [ ] Hook deployed and verified in local + staging environments
   - [ ] `cost_estimates` RLS policies migrated to use `jwt_has_project_permission`
   - [ ] pgTAP tests updated and passing for new JWT-based policies
   - [ ] Performance benchmarked against baseline (measure query times before/after)
   - [ ] Rollback plan documented and tested

   **Rollback Plan**: If issues arise, re-enable the original `user_has_project_permission` policies by restoring the previous migration. Keep both function implementations available during the transition period to allow quick rollback without data loss.

## References

- [Supabase Custom Access Token Hooks Documentation](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)
- [Supabase Row Level Security Guide](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [PostgreSQL JSONB Functions](https://www.postgresql.org/docs/current/functions-json.html)
