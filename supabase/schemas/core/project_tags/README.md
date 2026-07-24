# Project Tags Module

## Overview

`project_tags` is the many-to-many pivot linking `projects` to `tags`. It was
introduced in CA-596 so the `global_search` RPC's `filter_by_tag` parameter can
restrict project results to projects carrying a given tag. It mirrors the
`session_tags` pivot (which links `tags` to `calculation_sessions`), the only
pre-existing consumer of the `tags` reference table.

## Table Structure

- `id` - UUID primary key
- `project_id` - FK to `projects.id`, `ON DELETE CASCADE`
- `tag_id` - FK to `tags.id`, `ON DELETE CASCADE`
- `applied_at` - Timestamp when the tag was applied to the project

## Indexes

- `project_tag_uq` - `UNIQUE (project_id, tag_id)`; a tag can be applied to a
  project at most once. Doubles as the lookup index for the `global_search`
  tag-filter `EXISTS` probe, which enters by `project_id`.
- `project_tags_tag_id_idx` - Supports "all projects carrying tag X" lookups.

## RLS

- **SELECT** (`project_tags_select_policy`): follows project visibility via
  `user_has_project_permission(project_id, 'view_project', auth.uid())` — the
  same predicate as `projects_select_policy`. A user who cannot view a project
  cannot see its tag assignments either, including through the auto-exposed
  Data API.
- **INSERT/UPDATE/DELETE**: no policies defined. Write access is intentionally
  restricted to `service_role` / migrations only, matching the `tags`
  reference-data pattern (`tags` rows themselves are also read-only through
  the Data API).

**Asymmetry with `session_tags`:** `session_tags` predates this repo's RLS
policy conventions and has RLS enabled with no policies at all (fully closed
via the Data API). `project_tags` deliberately opens SELECT under project
visibility because `global_search` runs as `SECURITY INVOKER` and must be able
to evaluate the tag predicate as the calling user.

## Consumers

- `global_search` RPC (`supabase/schemas/global_search/global_search/03_functions.sql`):
  applies `filter_by_tag` to the projects result via an `EXISTS` probe against
  this table joined to `tags` by name.

## Related Tables

- `tags` — reference list of tag names (public SELECT).
- `projects` — the tagged entity; project deletion cascades here.
