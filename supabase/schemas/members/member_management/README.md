# Members — `member_management` Module

## Overview

Server-side RPCs implementing the member-management operations from the [CA-784](https://ripplearc.youtrack.cloud/issue/CA-784) Members design doc. All member mutations go through **SECURITY DEFINER RPCs** — no direct table writes — because the invariants are multi-row checks that RLS `WITH CHECK` expressions cannot express, and because permission checks must read the **database, never the JWT**: a stale token can therefore never authorize a write ("JWT staleness strategy").

Implemented across [CA-807](https://ripplearc.youtrack.cloud/issue/CA-807) (invite / respond / role change / removal + signup conversion) and [CA-808](https://ripplearc.youtrack.cloud/issue/CA-808) (project creation with members).

## Cross-cutting invariants

| # | Invariant |
| --- | --- |
| 1 | **Level rule** — a caller may only grant or change to roles with `level <= caller's level` |
| 2 | **Creator immutability** — the project creator's membership can never be role-changed or removed |
| 3 | **Self-service exception** — any member may remove *themselves* (leave), except the creator |
| 4 | **DB-side checks** — every permission/level check queries `project_members`/`role_permissions`, never JWT claims |

## RPCs (EXECUTE granted to `authenticated` only)

### `invite_project_members(p_project_id uuid, p_invites jsonb) → jsonb` (CA-807 2/4)

`p_invites` is `[{"email": ..., "role_id": ...}, ...]`. Per email:

- **Registered user** → `project_members(status='invited')` row plus a `project_invite` row in `notifications` (the Notifications feature renders Accept/Decline). A previously `declined` membership is re-invited in place (fresh `invited_at`, `joined_at` cleared). Outcome `invited`; existing `invited`/`joined` rows yield `already_member`.
- **Unregistered email** → upsert into `project_invitations(status='pending')` (latent until signup; v1 sends no email). Outcome `pending_signup`.

Checks: caller holds `invite_member` (DB), level rule per invite. Any invalid entry (unknown role, level violation, malformed invite) raises and rolls back the whole batch.

### `respond_to_invitation(p_project_id uuid, p_accept boolean) → void` (CA-807 2/4)

Sets the **caller's own** `invited` row to `joined` + `joined_at`, or `declined`. When the membership originated from an unregistered-email invite, the matching `pending` `project_invitations` row is marked `accepted`/`declined`. Raises `P0002` when the caller has no pending invitation.

### `update_member_role(p_project_id uuid, p_member_user_id uuid, p_new_role_id uuid) → void` (CA-807 3/4)

Changes a member's role (any membership status). Checks, in order: caller holds `update_member_role` (DB); the target is not the project creator (`42501`); the membership exists (`P0002`); the new role is a known project role (`22023`); the level rule holds on **both** sides — the member's current role and the new role must be ≤ the caller's level (`42501`). The target row is locked (`FOR UPDATE`) before the change.

### `remove_project_member(p_project_id uuid, p_member_user_id uuid) → void` (CA-807 3/4)

Deletes a membership. The creator can never be removed — not even by themselves (`42501`). Any member may remove **their own** row (leave project) without holding `remove_member`; removing someone else requires it. Missing membership raises `P0002`. Per the design doc, removal has **no level rule** — `remove_member` holders (Manager+) may remove any non-creator member.

### `create_project_with_members(p_project jsonb, p_invites jsonb DEFAULT '[]') → jsonb` (CA-808)

Transactionally creates the project, the creator's Admin `joined` membership (`invited_by` NULL, per the "Owner" display convention), and processes `p_invites` through `process_project_invites` — the creator's fresh Admin membership satisfies its `invite_member` check, and every invite invariant (level rule, role validation) applies unchanged. Any failure aborts the entire creation (single function = single transaction). Returns `{"project_id": ..., "outcomes": [...]}`. `creator_user_id` is always the caller — never client-supplied. Enables CA-163's `CreateProjectWithMembersUseCase`.

**Backfill** (same migration, `20260718105000_44_create_project_with_members.sql`): creator-membership Admin/`joined` rows for projects that predate the membership model, with `invited_at`/`joined_at` set to the project's `created_at`. Idempotent (`NOT EXISTS` + `ON CONFLICT DO NOTHING`), leaves any pre-existing creator membership untouched, and skips with a NOTICE when the Admin role is not seeded (e.g. local `db reset`, where seeders run after migrations).

## Signup conversion (CA-807 4/4)

`trigger_convert_pending_invitations` (`AFTER INSERT ON users`, see `04_triggers.sql`) calls `convert_pending_invitations()`: every `pending` `project_invitations` row whose `email` matches the new user's email (citext, case-insensitive) becomes a `project_members(status='invited')` row (preserving `role_id`, `invited_by_user_id`, `invited_at`) plus a `project_invite` notification. Conversion is idempotent per membership (`ON CONFLICT DO NOTHING`), and notifications are emitted only for rows actually converted. The invitation row stays `pending` until the user accepts/declines in-app — `respond_to_invitation` then marks it `accepted`/`declined`.

## Internal helpers (EXECUTE revoked from API roles)

- `internal_user_id_for_auth_uid() → uuid` — resolves `auth.uid()` → `users.id` via `credential_id`; raises `42501` when the caller has no profile row. The credential id itself is never returned or exposed.
- `process_project_invites(project_id, inviter_id, invites) → jsonb` — the shared invite-batch engine used by `invite_project_members` and `create_project_with_members` (CA-808), so the permission check, level rule, and registered/unregistered branching live in exactly one place.
- `member_permission_level(project_id, user_id, permission_key) → int` — the role level of a joined member holding the given permission, or NULL; the common "permission + level" lookup for the role-change/removal RPCs.

## Security notes

- All exposed RPCs: `SECURITY DEFINER`, `SET search_path = public`, `REVOKE ... FROM PUBLIC, anon`, `GRANT ... TO authenticated`.
- Internal helpers additionally revoke `authenticated`; they are reachable only through the definer RPCs (which execute as `postgres`).
- Error codes: `42501` (insufficient privilege) for permission/level violations, `22023` (invalid parameter) for malformed input, `P0002` (no data) for responding without a pending invite.
