# Members — `project_invitations` Module

## Overview

`project_invitations` carries member invites addressed to **email addresses with no Construculator account yet**. `project_members.user_id` is NOT NULL, so a pending invite for an unregistered person is unrepresentable there; per the CA-784 design doc this dedicated table was chosen over relaxing `project_members` (clean constraints, no leakage of pending rows into member queries, and a clear signup conversion state machine).

Introduced by [CA-807](https://ripplearc.youtrack.cloud/issue/CA-807).

## Lifecycle

1. `invite_project_members` (CA-807 RPC) upserts a `pending` row when the invited email has no `users` account. **v1 sends no email** — the invite is *latent*.
2. When a person signs up with that email, pending invitations convert into `project_members(status='invited')` rows plus a `project_invite` notification (signup-conversion trigger, CA-807 4/4). The invitation row stays `pending` at this point.
3. When the user accepts or declines in-app (`respond_to_invitation`), the invitation row is marked `accepted` / `declined`.
4. `revoked` is reserved for withdrawing a pending invite (no RPC exposes it yet).

## Table Structure

- `id` - UUID primary key
- `project_id` - FK to `projects.id`
- `email` - `citext` (case-insensitive matching against signup emails)
- `role_id` - FK to `roles.id` — the role the person will get on conversion
- `invited_by_user_id` - FK to `users.id` (NOT NULL — an invitation always has an inviter)
- `invited_at` - timestamptz, defaults to `now()`
- `status` - `invitation_status_enum` (`pending` | `accepted` | `declined` | `revoked`)
- `UNIQUE (project_id, email)` — re-inviting the same email upserts the existing row

## Indexes

- `email` — signup conversion looks pending invitations up by the new user's email
- `role_id`, `invited_by_user_id` — FK indexes, per repo convention
- `status` — pending-list rendering and conversion filtering
- `project_id` is covered by the leading column of the UNIQUE constraint

## RLS Policies

- **SELECT** — `jwt_has_project_permission(project_id, 'invite_member')`: members who can invite manage the pending list. Invitees themselves have no account yet, so no self-read clause is needed.
- **Writes** — no policies; all mutations go through the SECURITY DEFINER member-management RPCs.

## Migration Considerations

- Requires the `citext` extension (`CREATE EXTENSION IF NOT EXISTS`).
- Adds `invitation_status_enum` (see `schemas/_types/enums.sql`).
