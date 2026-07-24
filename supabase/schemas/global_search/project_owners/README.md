# Project Owners

Backend for the **Owner filter** sheets in global search and dashboard
project search ([CA-839](https://ripplearc.youtrack.cloud/issue/CA-839),
under epic [CA-497](https://ripplearc.youtrack.cloud/issue/CA-497)).

The app's `RemoteOwnerDataSource` calls the `get_project_owners` RPC with no
arguments and renders the returned profiles in the owner
`MultiSelectFilterSheet`; the selected ids are then passed to
`global_search`'s `filter_by_owners uuid[]` parameter (CA-737).

| File | Contents |
|------|----------|
| `03_functions.sql` | `get_project_owners()` — distinct creators of the caller-visible projects. |

## Semantics

- **Visibility** — `SECURITY INVOKER`: the projects RLS policy
  (`user_has_project_permission(id, 'view_project', auth.uid())`) decides
  which projects contribute owners. An unauthenticated caller gets zero rows.
- **Profile columns** — read via the `user_profiles` view (the deliberate
  public subset of `users`), so peers' names resolve despite `users`'
  select-own RLS. The return signature pins exactly
  `id, first_name, last_name, professional_role, profile_photo_url`; never
  add `credential_id` or `email` (see the privacy note in the function and
  the `function_returns` pin in
  `supabase/tests/functions/get_project_owners_test.sql`).
- **Deduplication** — one row per creator regardless of how many visible
  projects they own; ordered by `first_name, last_name` for a stable sheet.
