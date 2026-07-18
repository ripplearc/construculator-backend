# Members — `project_members` Module

## Overview

`project_members` holds one row per (project, user) membership, carrying the member's role and invitation lifecycle. It is the source of truth for RBAC: the custom access token hook aggregates each user's `joined` memberships into per-project permission arrays in the JWT (`app_metadata.projects`), and `roles`/`role_permissions` define what each role may do.

This module documents the member-management hardening introduced by [CA-806](https://ripplearc.youtrack.cloud/issue/CA-806) (from the CA-784 Members design doc). The table itself predates the `schemas/` folder (migration `20250514093708_14_project_members.sql`) and is listed below for reference only.

## Table Structure (for reference — defined in migration 14)

- `id` - UUID primary key
- `project_id` - FK to `projects.id`
- `user_id` - FK to `users.id` (NOT NULL — invites to unregistered emails live in `project_invitations`, see CA-807)
- `role_id` - FK to `roles.id`
- `invited_by_user_id` - FK to `users.id`, nullable (NULL for e.g. the project creator)
- `invited_at` - timestamptz, defaults to `now()`
- `joined_at` - timestamptz, set when the invitation is accepted
- `membership_status` - `membership_status_enum` (`invited` | `joined` | `declined`)
- `UNIQUE (project_id, user_id)`

## Roles & Permission Matrix (CA-806)

Canonical role levels: **Admin 4 / Manager 3 / Collaborator 2 / Viewer 1**. CA-806 fixed Viewer from level 2 (tied with Collaborator) to 1, so the "assign roles no higher than your own level" rule forms a strict hierarchy.

Member-management permission keys seeded by CA-806:

| Permission key | Viewer | Collaborator | Manager | Admin |
| --- | --- | --- | --- | --- |
| get_members | ✅ | ✅ | ✅ | ✅ |
| invite_member | ❌ | ✅ | ✅ | ✅ |
| update_member_role | ❌ | ❌ | ✅ | ✅ |
| remove_member | ❌ | ❌ | ✅ | ✅ |
| get_task_assignments | ❌ | ✅ | ✅ | ✅ |

## RLS Policies

### SELECT — `project_members_select_policy`

```sql
"user_id" = (SELECT public.jwt_internal_user_id())
OR public.jwt_has_project_permission("project_id", 'get_members')
```

- Replaces the pre-CA-806 policy that let **any** authenticated user read **all** membership rows.
- The first clause is required because the JWT `projects` claims only cover `joined` memberships — without it, an *invited* user could not see their own pending row.
- Both clauses read only JWT claims (no table access), so the policy is O(1) per row, cannot recurse, and the `(SELECT ...)` wrapper lets the planner cache the caller's id as an InitPlan.

### Writes

No INSERT / UPDATE / DELETE policies: membership mutations go exclusively through the SECURITY DEFINER member-management RPCs (CA-807/CA-808), which validate the level rule and creator immutability against the database.

## Related shared functions (`schemas/_shared/01_functions.sql`)

- `jwt_internal_user_id()` — the caller's internal `users.id` from `app_metadata.internal_user_id` (added by CA-806).
- `user_has_project_permission(project_id, key, credential_id)` — database-side permission check used by the `projects` and cost-table RLS policies. CA-806 made it **SECURITY DEFINER** (with pinned `search_path`): it previously relied on the permissive read policy this module removed, and a permission check must not depend on the caller's RLS visibility of `project_members`.

## Migration Considerations

- CA-806 changes are additive/idempotent: permission inserts use `ON CONFLICT DO NOTHING`; the Viewer level update is guarded by `AND level = 2`.
- Clients holding tokens issued **before** the auth hook started injecting `internal_user_id` (migration `20260413004017`) would fail the first policy clause; token TTL (≤ 1 h) bounds that window.
