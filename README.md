# Construculator Backend

Database backend for **Construculator** — a construction cost estimation platform built on [Supabase](https://supabase.com). This repository contains all database migrations, schema definitions, seeders, tests, and CI configuration.

---

## Table of Contents

- [Tech Stack](#tech-stack)
- [Resources](#resources)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Schema-Based Declarative Structure](#schema-based-declarative-structure)
- [Migrations](#migrations)
- [Seeders](#seeders)
- [Database Testing](#database-testing)
- [Row Level Security (RLS)](#row-level-security-rls)
- [Local Services & Ports](#local-services--ports)
- [Viewing OTP Codes](#viewing-otp-codes)
- [Linking the Test User to Supabase Auth](#linking-the-test-user-to-supabase-auth)
- [Common Commands](#common-commands)
- [CI / CD](#ci--cd)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Database  | PostgreSQL 15 (via Supabase) |
| API       | PostgREST (auto-generated REST) |
| Auth      | Supabase Auth (JWT, email OTP) |
| Security  | Row-Level Security (RLS) policies |
| Testing   | pgTAP (SQL-native database tests) |
| CI        | GitHub Actions |

---

## Resources

- **Internal Documentation (Wiki):** [Project Wiki (docs/)](./docs/Home.md)
- **Backend Database Schema:** [Google Doc](https://docs.google.com/document/d/144-j6mZluSGtFXZdF23cVf9hbVWt4vb-wA3eq02Au4M)
- **Supabase Documentation:** [https://supabase.com/docs](https://supabase.com/docs)

---

## Prerequisites

- **Docker** — must be running before starting Supabase
- **Node.js** ≥ 18
- **npm**

---

## Getting Started

```bash
# 1. Make sure you are inside the repo
cd construculator-backend

# 2. Install dependencies (includes Supabase CLI)
npm install

# 3. Verify Supabase CLI
npx supabase --version

# 4. Start all local services (Docker must be running)
npx supabase start
```

On first run, Supabase will pull Docker images, apply all migrations, and seed the database. When it finishes you'll see connection details:

```
API URL:      http://127.0.0.1:54321
Database URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
Studio URL:   http://127.0.0.1:54323
Inbucket URL: http://127.0.0.1:54324
```

---

## Project Structure

```
construculator-backend/
├── supabase/
│   ├── config.toml              # Supabase local configuration
│   ├── migrations/              # Ordered SQL migrations (source of truth)
│   ├── schemas/                 # Declarative schema modules (reference design)
│   │   ├── _types/              #   Shared enums and custom types
│   │   └── cost_management/     #   Domain modules (cost_estimates, cost_items, …)
│   ├── seeders/
│   │   ├── constants/           #   System-level seed data (permissions)
│   │   └── sample_data/         #   Development test data
│   ├── tests/
│   │   ├── database/            #   pgTAP integration tests
│   │   └── functions/           #   RPC / edge function tests
│   └── templates/               # Email templates
├── docs/                        # Wiki documentation (auto-synced to GitHub Wiki)
├── scripts/                     # Developer utility scripts
├── .github/
│   ├── workflows/               # CI pipelines
│   └── CODEOWNERS               # Code review ownership
└── package.json
```

---

## Schema-Based Declarative Structure

> **We are actively migrating from the legacy migration-based approach to a schema-based declarative structure.** New features should be authored in `schemas/` first. The `migrations/` directory contains historical migrations and will continue to be applied for backwards compatibility, but all new database design work targets the schema modules.

### How It Works

The `supabase/schemas/` directory contains modular, self-contained SQL definitions organized by domain. Each module follows a consistent layout:

```
schemas/cost_management/cost_estimates/
├── 01_table.sql        # Table definition
├── 02_indexes.sql      # Performance indexes
├── 03_functions.sql    # Trigger functions & stored procedures
├── 04_triggers.sql     # Trigger bindings
├── 05_views.sql        # Views
├── 06_rls.sql          # Row-Level Security policies
└── README.md           # Module documentation (MUST be kept up-to-date)
```

> **Rule:** Whenever you modify any SQL file in a schema module, **always update that module's `README.md`** to reflect the change. The README is the first place other developers look to understand a module's behavior.

### Benefits Over Migrations

- **Readable** — Each module shows the complete, current state of a table in one place instead of scattered across dozens of migration files.
- **Reviewable** — PRs show the full picture of a feature (table + indexes + functions + triggers + RLS) in a single directory.
- **Self-documenting** — Every module includes a `README.md` with business rules, permissions, and usage examples.
- **Modular** — Concerns are separated into numbered files that can be understood independently.

### Execution Order via `config.toml`

Schema files are **order-dependent** — tables must be created before their foreign keys, functions before their triggers, etc. The execution order is controlled by the `schema_paths` array in `supabase/config.toml`:

```toml
[db.migrations]
schema_paths = [
  # Types and Enums (must come first)
  "./schemas/_types/enums.sql",

  # Core tables
  "./schemas/core/users/*.sql",
  "./schemas/projects/projects/*.sql",

  # Domain modules (depend on core tables)
  "./schemas/cost_management/cost_estimates/*.sql",
  "./schemas/cost_management/cost_items/*.sql",
  "./schemas/cost_management/cost_estimate_logs/*.sql",

  # ... remaining modules in dependency order
]
```

**Key points:**
- Glob patterns (`*.sql`) expand files in **alphabetical order** within each module — this is why files are numbered (`01_table.sql`, `02_indexes.sql`, …).
- When adding a new module, insert its glob pattern in the correct position relative to its dependencies.
- The seed file order is similarly controlled via `sql_paths` under `[db.seed]`.

#### When Globs Aren't Enough

Sometimes a module has cross-dependencies that break simple glob ordering. For example, the `projects` module's RLS policies depend on a shared helper function, which itself depends on `project_teams` and `project_members` tables. In these cases, list individual files to interleave dependencies:

```toml
# Projects — split to interleave dependencies
"./schemas/projects/projects/01_table.sql",
"./schemas/projects/projects/02_indexes.sql",
"./schemas/projects/projects/03_functions.sql",
"./schemas/projects/projects/04_triggers.sql",
"./schemas/projects/project_teams/*.sql",
"./schemas/projects/project_members/*.sql",
"./schemas/_shared/user_project_permission.sql",   # shared function needed by RLS
"./schemas/projects/projects/05_rls.sql",           # now safe to reference everything above
```

Use explicit file paths whenever a module's later files (like RLS) depend on other modules being loaded first.

### Generating Migrations with `supabase db diff`

When you modify schema files, use `npx supabase db diff` to auto-generate the migration SQL from the difference between your schema definitions and the current database state:

```bash
# 1. Make your changes in schemas/
# 2. Generate a diff-based migration
npx supabase db diff -f <migration_name>

# 3. Review the generated file in supabase/migrations/
# 4. Reset and verify
npx supabase db reset && npx supabase test db
```

This avoids writing migration SQL by hand — the CLI compares the declared schema against the running database and produces the exact `ALTER` / `CREATE` / `DROP` statements needed.

> **Caveat:** The schema diff tool handles most Postgres objects (tables, indexes, functions, triggers, RLS policies), but **DML statements** (e.g. `INSERT`, `UPDATE`, `DELETE`) and some procedural logic are not captured. These cases (if there are any) still require manual migrations.


Each module's `README.md` documents table structure, business rules, triggers, and RLS policies in detail.

---

## Migrations (Legacy)

Existing migrations in `supabase/migrations/` are still applied in filename-sorted order on `npx supabase start` and `npx supabase db reset`. They remain the execution mechanism for tables not yet migrated to the schema-based structure.

```
YYYYMMDDHHMMSS_<description>.sql
```

The migration set covers:
- **01–31** — Core tables (types, roles, permissions, users, projects, cost estimates, threads, notifications, etc.)
- **enable_rls** — Enables RLS on all tables
- **RLS_01–07** — Incremental RLS policy additions
- **soft_delete / cascade** — Soft-delete and cascade behavior for cost management
- **activity_logging** — Centralized trigger-based activity logging

---

## Seeders

Seeders run automatically on `npx supabase start` and `npx supabase db reset`. They are split into two categories:

### Constants (`seeders/constants/`)
System-level data that must exist for the app to function:
- **Permissions** — `get_cost_estimations`, `add_cost_estimation`, `delete_cost_estimation`, `edit_cost_estimation`, `lock_cost_estimation`, `view_project`, `edit_project`, `delete_project`

### Sample Data (`seeders/sample_data/`)
Development/test data applied in numbered order:

| File | Seeds |
|------|-------|
| `101_professional_roles` | 5 roles (Project Manager, Cost Estimator, Construction Manager, Architect, Engineer) |
| `102_companies` | Sample companies |
| `103_users` | Test user (`seeder@example.com`) |
| `104_projects` | 4 sample projects |
| `105_cost_estimates` | 6 cost estimates with various markup configurations |
| `106_roles_and_role_permissions` | 4 project roles (Admin, Manager, Collaborator, Viewer) with permission mappings |
| `107_project_members` | Sample project memberships |

---

## Database Testing

Tests use **pgTAP** and live in `supabase/tests/`. Run them with:

```bash
npx supabase test db
```

### Test Coverage

| Test File | What It Covers |
|-----------|---------------|
| `core_schema_smoke_test` | All tables exist and are accessible |
| `core_relationships_test` | Foreign key relationships are valid |
| `critical_tables_insert_and_columns_test` | Column definitions on critical tables |
| `cost_estimates_test` | CRUD operations on cost estimates |
| `cost_estimates_update_guard_test` | Immutable field enforcement, lock permissions |
| `cost_items_test` | Cost item operations and triggers |
| `cost_estimate_logs_test` | Audit log entries |
| `cost_estimate_activity_logging_test` | End-to-end activity logging via triggers |
| `cascade_delete_test` | Soft-delete cascade behavior |
| `check_email_exists_test` | Email lookup RPC function |

> Tests are **required to pass** on every PR — CI will block merge on failure.

---

## Row Level Security (RLS)

All tables have RLS enabled. This is the **most common source of "empty results"** when querying from the client app.

### Quick Diagnosis

| Symptom | Cause |
|---------|-------|
| Query returns `[]` but Studio shows data | RLS is blocking — no matching policy for the current user |
| Works in Studio but not in app | Studio uses the `service_role` key which bypasses RLS |

### How Policies Work

```markdown
Policies are defined per-table and per-operation (`SELECT`, `INSERT`, `UPDATE`, `DELETE`). They typically check:

- **Ownership**: Comparing `auth.uid()` to a column like `user_id`.
- **Membership**: Verifying the user exists in a related table (e.g., `project_members`).
```

```sql
-- Example: user can view projects they belong to
CREATE POLICY "Members can view their projects" ON public.projects
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.project_members
    WHERE project_members.project_id = projects.id
    AND project_members.user_id = (
      SELECT id FROM public.users WHERE credential_id = auth.uid()
    )
  )
);
```

### Key Points

- **`service_role` key bypasses RLS** — never expose it to the client.
- **Functions can bypass RLS** by using `SECURITY DEFINER`. When doing so, always include `SET search_path = public` to prevent search path hijacking.

  ```sql
  -- Example: Function bypassing RLS to count all users
  CREATE OR REPLACE FUNCTION get_user_count()
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  BEGIN
    RETURN (SELECT count(*) FROM public.users);
  END;
  $$;
  ```

- **Policy names must be unique** per table.
- When adding a feature that needs new policies, add them in the appropriate schema module's `_rls.sql`.

### Column-Level Security via Views

RLS controls *which rows* a user can access, but it doesn't restrict *which columns* are visible. When you need to expose only a subset of a table's fields — for example showing a user's public profile without leaking sensitive data like `email` or `user_preferences`. Create a **view** that selects only the permitted columns, then grant access to the view instead of the underlying table.

**Example — `user_profiles` view:**

The `users` table holds sensitive fields (`email`, `phone`, `user_preferences`) that other users should never see. A view exposes only the safe public fields:

```sql
-- supabase/migrations/20251218175411_create_user_profile_view.sql
CREATE OR REPLACE VIEW "user_profiles" AS
SELECT
  id,
  credential_id,
  first_name,
  last_name,
  professional_role,
  profile_photo_url
FROM "users";
```

The RLS on the underlying `users` table restricts full access to the row owner only. The view is then granted selectively to all authenticated users:

```sql
-- supabase/migrations/20251218175536_RLS_07_users_table_rules.sql

-- Owners get full access to their own row in the base table
CREATE POLICY "users_owner_full_access" ON "users"
  FOR ALL
  TO authenticated
  USING (auth.uid() = credential_id)
  WITH CHECK (auth.uid() = credential_id);

-- All authenticated users can read the safe public view
GRANT SELECT ON "user_profiles" TO authenticated;
```

**The result:**

| Access path | Who can use it | What they see |
|-------------|----------------|---------------|
| `SELECT * FROM users` | Owner only (via RLS) | All columns including `email`, `user_preferences` |
| `SELECT * FROM user_profiles` | Any authenticated user | `id`, `credential_id`, `first_name`, `last_name`, `professional_role`, `profile_photo_url` only |

**When to use this pattern:**
- Any table with a mix of private and shareable fields.
- Avoid granting direct `SELECT` on the base table to roles that only need partial data.
- In schema modules, define views in `05_views.sql` and keep RLS policies in `06_rls.sql`.

---

## Local Services & Ports

| Service | Port | URL | Use For |
|---------|------|-----|---------|
| **API (PostgREST)** | 54321 | `http://localhost:54321` | REST API — use in your app |
| **Database (Postgres)** | 54322 | `postgresql://postgres:postgres@localhost:54322/postgres` | Direct SQL access |
| **Studio** | 54323 | `http://localhost:54323` | Browse data, run queries, manage auth |
| **Inbucket (Email)** | 54324 | `http://localhost:54324` | View test OTP/email |
| **Analytics** | 54327 | `http://localhost:54327` | Log management |

---

## Viewing OTP Codes

When testing signup or password reset, emails are intercepted by **Inbucket** (not actually sent):

1. Open `http://localhost:54324`
2. Find the email for your test user
3. Copy the 6-digit OTP from the email body

---

## Linking the Test User to Supabase Auth

The seeded user (`seeder@example.com`) has a placeholder `credential_id`. To authenticate properly, link it to a real Supabase Auth user:

1. **Create the auth user** — In Studio (`http://localhost:54323`) → Authentication → Users → Add User → enter email `seeder@example.com` and a password.
2. **Copy the User UID** from the auth users list.
3. **Update the users table** — In Table Editor → `users` table → find `seeder@example.com` → paste the UID into the `credential_id` field.
4. **Verify** — Log in through the app. RLS policies should now work correctly.

> **Why?** The `credential_id` column links a `users` row to its Supabase Auth identity (`auth.uid()`). Without this match, RLS policies will deny access.

---

## Common Commands

| Action | Command |
|--------|---------|
| Start Supabase | `npx supabase start` |
| Stop Supabase | `npx supabase stop` |
| View status | `npx supabase status` |
| Reset database | `npx supabase db reset` |
| Run tests | `npx supabase test db` |
| Diff schema → migration | `npx supabase db diff -f <name>` |
| Create empty migration | `npx supabase migration new <name>` |
| Apply migrations | `npx supabase migration up` |
| View logs | `npx supabase logs` |

---

## CI / CD

### Database Tests (PR Gate)

Every pull request that touches `supabase/**/*.sql` triggers the **Database Integration Tests** workflow:

1. Starts a fresh Supabase instance
2. Applies all migrations
3. Runs `supabase test db` (pgTAP)

> `[skip ci]` and `[ci skip]` in commit messages are explicitly **blocked** — tests always run.

### Wiki Sync

Pushing changes to `docs/` on the `master` branch automatically syncs content to the GitHub Wiki.

---

## Troubleshooting

#### Not able to initiate Supabase

**Symptom:** App repeatedly crashes after ```supabase start```.

**Workaround:**
1. Reset and reseed local Supabase (no backup):
```bash
npx supabase stop --no-backup
```

#### Migration Errors

**Symptom:** `supabase start` fails with migration errors.

**Fix:**
1. Check migration files in `supabase/migrations/`
2. Look for syntax errors or broken references
3. Reset database:
   ```bash
   npx supabase db reset
   ```
4. If problem persists, check the [construculator-backend](https://github.com/ripplearc/construculator-backend) repo for updates

---

## Contributing

1. **Branch** off `master`.
2. **Design** your change in the appropriate `schemas/` module — update or create the table, functions, triggers, RLS, and README files.
3. **Generate a migration** with `npx supabase db diff -f <name>` to auto-produce the incremental SQL, or use `npx supabase migration new <name>` and write it manually.
4. **Write tests** in `supabase/tests/database/` using pgTAP.
5. **Reset and verify** locally: `npx supabase db reset && npx supabase test db`.
6. **Open a PR** — CI will validate your migration and tests automatically.

> **Schema-first rule:** If a schema module exists for the area you're changing, update the schema files **and the module's README.md** *before* generating the migration. If no module exists yet, consider creating one as part of the ongoing migration effort.
