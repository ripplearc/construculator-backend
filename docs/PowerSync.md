# PowerSync Integration Wiki
**Construculator · Offline-First Architecture · PowerSync + Supabase + Flutter**

---

## Table of Contents
1. [What is PowerSync?](#1-what-is-powersync)
2. [Core Concepts](#2-core-concepts)
3. [Frequently Asked Questions](#3-frequently-asked-questions)
4. [How PowerSync Works with Supabase](#4-how-powersync-works-with-supabase)
5. [Sync Streams Configuration](#5-sync-streams-configuration)
6. [Flutter SDK Integration](#6-flutter-sdk-integration)
7. [Security Model](#7-security-model)
8. [Local Development & Deployment](#8-local-development--deployment)
9. [Pricing & Infrastructure](#9-pricing--infrastructure)
10. [Migration Guide](#10-migration-guide)
11. [Common Pitfalls](#11-common-pitfalls)

---

## 1. What is PowerSync?

PowerSync is a sync engine that enables offline-first mobile and web apps. It sits between the backend database (Supabase Postgres, in this case) and each user's device, keeping a local SQLite copy of the data that each user is allowed to see — automatically, in real time.

The core promise is simple: the app reads and writes to a local database instantly, with no network latency. PowerSync handles syncing those changes to and from the backend in the background — even when the user is offline.

> **Why does this matter for Construculator?**
> Construction sites often have poor or no connectivity. Users need to be able to view and edit cost estimates, add line items, and make project changes without waiting for a network round-trip. With PowerSync, all of this works offline and syncs when connectivity is restored.

### The Three-Layer Stack

```
Supabase Postgres  →  PowerSync Service  →  PowerSync SDK (Flutter)  →  Local SQLite
```

Each layer has a distinct responsibility:

- **Supabase Postgres** — the source of truth. All data ultimately lives here. RLS policies protect server-side API access.
- **PowerSync Service** — the sync engine. Replicates data from Postgres, applies stream rules to decide what each user sees, and streams deltas to devices.
- **Flutter app + PowerSync SDK** — local SQLite database on the device. The app only ever talks to this local DB; the SDK handles sync in the background.


---

## 2. Core Concepts

### WAL Replication

PowerSync connects to Postgres as a logical replication client and listens to the Write-Ahead Log (WAL) — the same mechanism Postgres uses for crash recovery and read replicas. Every INSERT, UPDATE, and DELETE on replicated tables is streamed to PowerSync as a change event. PowerSync never runs SELECT queries against the tables directly.

On first setup, PowerSync performs a one-time snapshot read to bootstrap the initial data. After that, it is purely event-driven.

### Buckets

Internally, PowerSync partitions data into buckets — think of a bucket as a named container of rows for a specific user or context. When a user connects, they only receive the buckets that belong to them.

With Sync Streams (the modern approach used in Construculator), buckets are created implicitly based on stream queries. They are not defined manually. For example, a stream scoped to a `project_id` creates one bucket per unique project per user — so a user in 5 projects gets 5 buckets, each containing that project's rows.

> 💡 **Bucket limit:** PowerSync has a default limit of 1,000 buckets per user. This is generous for most apps, but should be considered when designing streams with many granular parameters.

### Sync Streams

A Sync Stream is a named, queryable subscription to a slice of data. Streams are defined in a YAML config file deployed to the PowerSync instance. Each stream has:

- **A query** — SQL-like statement defining which rows belong to this stream
- **Optional CTEs (`with` block)** — Common Table Expressions for authorization logic, such as membership checks
- **`auto_subscribe`** — if `true`, clients subscribe automatically on connect (good for always-needed data)
- **`subscription.parameter()`** — values the client passes when subscribing on-demand (e.g., opening a specific project)

### auth.user_id()

Inside stream queries, `auth.user_id()` returns the `sub` claim from the user's JWT — the Supabase Auth user ID. This is signed by Supabase and trusted by PowerSync. It is the primary mechanism for scoping data to the authenticated user.

### Auto-subscribe vs On-Demand

| | `auto_subscribe: true` | On-Demand |
|---|---|---|
| **When syncs** | On connect, always active | When client explicitly subscribes |
| **Use for** | Profile, projects, memberships | Cost Estimate Data for a specific project |
| **Parameters** | Only `auth.user_id()` | `subscription.parameter('x')` |

---

## 3. Frequently Asked Questions

### Q: Who is responsible for maintaining the local SQLite database?

Maintenance is a "relay race" between you and the SDK:

- **You (the Architect)**: Define the schema in your Dart code (see Section 5, Step 1). You declare what tables and columns should exist locally.
- **PowerSync SDK (the Manager)**: Physically creates the tables in SQLite and keeps the data inside them updated in real-time via sync.

You never write raw `CREATE TABLE` SQL — the SDK handles that automatically based on your schema definition.

### Q: Does PowerSync automatically create the tables in the local database?

**Yes.** When your Flutter app initializes, the PowerSync SDK:

1. Compares your Dart `Schema` definition against the local SQLite file
2. Creates any missing tables automatically
3. Applies schema changes when you update your Dart code

You only define the schema in Dart — the SDK executes all the `CREATE TABLE` and `ALTER TABLE` commands for you.

### Q: Do I have to "explicitly" sync every table?

**Yes.** PowerSync only replicates tables that appear in a `SELECT` statement within your Sync Streams configuration (see Section 4).

**Important:** If you add a table to Postgres but forget to add it to your PowerSync YAML config, no data for that table will ever reach user devices. This is intentional — it gives you fine-grained control over what syncs.

### Q: When I update my Supabase Postgres database, what else do I need to update?

It depends on the type of update:

| Update Type | PowerSync | Flutter Schema | What Happens |
|---|---|---|---|
| **New rows** (INSERT/UPDATE/DELETE) | No change needed | No change needed | Automatic — PowerSync listens to WAL and pushes changes to devices |
| **New columns in synced table** | Update Sync Stream query to SELECT new columns | Add columns to Dart schema | Both required — if you only update one, data won't sync correctly |
| **New table** | Add new stream with SELECT query | Add new Table() to schema | Both required — table won't sync without stream config |
| **Dropped columns** | Remove from SELECT query | Remove from Dart schema | Both recommended for consistency |

**Key Rule:** The columns in your Sync Stream `SELECT` statements must match the columns in your Flutter `Schema` definition. Any mismatch causes silent data loss (see Section 10, Common Pitfalls).

### Q: What happens if a write is rejected by Supabase (e.g., an RLS Denied error)?

This is a critical scenario:

1. **Local State**: The optimistic change remains in your local SQLite database
2. **Upload Queue**: PowerSync stops retrying that transaction (if error handling is implemented correctly — see Section 5, Step 2)
3. **Server State**: The change never reaches Supabase; server data is unchanged
4. **User Experience**: The app should surface a conflict notification (requires custom UI implementation)

**Without proper error handling**, an RLS denial will cause PowerSync to retry indefinitely, blocking the entire upload queue and preventing any subsequent writes from reaching the server.

**Solution**: Implement the error handling pattern shown in Section 5, Step 2, which distinguishes permanent failures (RLS denials) from transient failures (network timeouts).

### Q: How do I know if my RLS policies will reject a write?

Test your RLS policies before deploying:

```sql
-- Test as a specific user
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims.sub = 'user-uuid-here';

-- Try the write that your app will attempt
UPDATE cost_estimates
SET estimate_name = 'New Name'
WHERE id = 'estimate-uuid';

-- Check for "permission denied" errors
```

Also review the Conflict Resolution Strategy in Section 3 for how to handle rejected writes gracefully.

---

## 4. How PowerSync Works with Supabase

### Authentication Flow

PowerSync does not have its own auth — it delegates entirely to Supabase Auth via JWT validation.

![Authentication Flow](https://mermaid.ink/svg/pako:eNptk9tq20AQhl9lmKsWFKOT1XgvAiVNLtIWTJU2UAxlvRrLi6VddQ8krvG7d1eJRZNauljN_N8cJR1Q6IaQIVj67UkJ-iR5a3i_UjBeAzdOCjlw5eC7JXPO_3EYgFu47bxzZKJ5lvJuG7HaD3zNLY2Oc-CyjthSP5Kp90qcQ-4ePo_QeN6oZtBSuZU6obHRi6ur0AiDL7qVkxA80R8KM6hlq0AqMHFw6yYkiBPzg3ey4Y5AGGpIOck7-wo8Vbl7uId3XAiy9l7vSL1fvam5rBlca6VIOHiUYRMh4kQs6wDEURjckhNbGPy6kwJ2tJ-qRfniJc83ct6oV_KYImpTx2_zR_HmyRkeGvBhP79kAxuje7B-_R8Yeu72YJ0h3kNYj5H0b6nT1PUzENPB2osdOYsJtkY2yJzxlGBPpufRxEOMX6HbUk8rZOEx3OoY-PBGf2rdn0KM9u0W2SasOlh-iNO8fJQTQqohc629csiKqhpzIDvgE7K8yGdpkVdFtpgXl3m1uExwjywry1lWzvNFVn0o07Sqjgn-Gaums8Cli7xclGkWznmRIDXSafP1-dcQWm1ki8e_51X79Q)

### Data Flow: Reads

All reads in the Flutter app come from the local SQLite database, not from Supabase directly (unless an online-first fetch is explicitly needed). This is what makes the app instant and offline-capable.

![Read Flow](https://mermaid.ink/svg/pako:eNptklFvmzAQx7-Kdc80BRIC-KFSVFhULatYyTRp4sWFK7EKNjN2uyzKd58hJWuk-Ml3_5__5zv7AKWsECj0-NugKDHhrFasLQQZV8eU5iXvmNAkWxPWk9x07Jn1SDLZ61phfxXNBzST76jyvSivIXny9YIZEle57xuucUA3smTNR3yNXHXdgH1pjNaohrAQE5etb-7usjUlD495-rS9_ZElq216m6SbdJteQjklP1cbgm8o9FnJPxRr2uxJrxWyltiJKf5_AGcoQVu_5QKJ6e1Fnk35ivoSs81Skp9sKmw0m1QrDPLY5FSu3DFRD3UmyKY_Qblt4n473mZ_thm1G0tZlpIn1EYJouT7J5dHaecq306jcia3B9FrO02nEOBArXgFVCuDDrS2JzaEcBgcCtA7bLEAareVei2gEEd7xD7FLynb6ZSSpt4BfWFNbyPTVUxPf-ycVSgqVPfSCA3U88PRBOgB_gBduMEsir3Ai4J4EfhLP3BgD9R3lzMvcGN36UeLuTf3oqMDf8e67iwI_NCbB6Efh1EczhcOYMW1VN9OX72U4oXXcPwHIqfsPw)

### Data Flow: Writes

Writes go to the local SQLite database first (optimistic), then get uploaded to Supabase via the backend connector. PowerSync queues writes and retries automatically on failure.

![Write Flow](https://mermaid.ink/svg/pako:eNptVG1P2zAQ_iuWP4EUuqQlgVoTEqIMTXRbWbVNmvrFtY_WIrGDXwoM8d93rpOOUfLF8T3P3T3nO_uZCiOBMurgPoAWMFF8ZXmz0AS_lluvhGq59uSHA7tvPW9bwh35VAfvwcbtPmd-M1UeIm1qBK-7_Tu8yXUkzcwD2PmTFtGwz7owWkdaXEF4846o2VUkzEPLl9wBBnR-ZcEtdKLGSo7OzlArI5dSeSK55wlCGyJJICNyOYBHEMHDwWHCE3LUe8-DEOAcOVDaecx82KfoeBhqcs3IBW99sEDEmutVVzgCPXwTIAAJbW24fA3GCllnn6DEXkS0Izy7YuR89pnY2DnnEza76pCfvFZYF5Dv03mvite-l5wMncdOp9G3yjYg_0M78Nf5lLjYlSUXd4kAtdvGJxPQCiQ5OB6WeXH4NnaqYwa2Uc4po4lMdLC2796rshLbPw6Eadoa4tkTbwiXG47jSe7jYb1x2jWzwWYKLKJWwhPYgPb_mF8NHobZpCHN4gxg_9bmIckgUvHarNjHpf1wtqB7YgdbIM1vaiNpcaTAbhBb0PfS9FP0rfUKg-F07jzBOjQ4Usd49VN3mlrSjK6skpR5GyCjDargcUufI2VB_RoaWFCGv9LexbQv6IIz_9uYpveyJqzWlN1y7E5GQxunoLvVO6vFZGAvTNCesqrcxqDsmT5SVuT54Lgq8rIcDXEpRqOMPqF5PBwUZXFS5cfVOM_Hpy8Z_bPNmg-qk2E5Lk_LvBpV1WmRUcBbZeyX9LJsH5heyOUW6aXy4E286Wn_8hdDz3HI)

> ✅ **Supabase is still the source of truth.** PowerSync is a sync layer, not a database replacement. All business logic, validation, and authorization for writes still runs on Supabase (via RLS, triggers, and edge functions). PowerSync just ensures the results of those writes get propagated back to all relevant devices.

### Conflict Resolution Strategy

When multiple users edit the same data offline, conflicts are routine in an offline-first architecture. Construculator uses the following conflict resolution approach:

**Strategy: Server-Authoritative with Client Notification**

| Scenario | Behavior | Resolution |
|---|---|---|
| **Concurrent edits, same record** | Last-write-wins based on server-side `updated_at` timestamp | Server accepts the last write; earlier writes are overwritten |
| **RLS violation (permission denied)** | Upload rejected, optimistic local change persists | Client notified via error handler; user must manually resolve or discard |
| **Lock conflict (cost estimates)** | Upload rejected if `is_locked` by another user | Client checks `is_locked` field; shows "locked by [user]" UI; must wait for unlock |
| **Stale read during offline period** | User edits based on outdated data | Last-write-wins applies; no automatic merge; consider adding `updated_at` checks in RLS |

**Implementation Details:**

1. **Optimistic UI**: All writes go to local SQLite immediately. The app shows changes instantly, even if offline.

2. **Server Validation**: When online, PowerSync uploads queued writes to Supabase. RLS, triggers, and business logic validate each change.

3. **Conflict Detection**:
   - **RLS denials** are caught in `uploadData()` error handler (see Section 5, Step 2)
   - **Lock conflicts** are enforced by `is_locked` field checks in Supabase RLS policies
   - **Concurrent edits** are implicitly resolved by Postgres write semantics (last write wins)

4. **User Notification**:
   - For RLS denials: App should emit a conflict event to UI layer (see `uploadData()` TODO comment)
   - For lock conflicts: App checks `is_locked` field before showing edit UI
   - For stale data: Consider adding UI warnings if `updated_at` field is older than a threshold

**Best Practices:**

- **Use `updated_at` timestamps**: Always include `updated_at` fields and update them on every write
- **Check locks before editing**: Query `is_locked` status before allowing edits to cost estimates
- **Surface conflicts to users**: Don't silently fail - show clear messages when writes are rejected
- **Consider optimistic locking**: For critical updates, add `updated_at` version checks in RLS policies to detect stale writes

**What PowerSync Does NOT Handle:**

- Automatic three-way merge of concurrent field-level changes
- Custom conflict resolution logic (e.g., user-selectable "keep mine" vs "keep theirs")
- Conflict-free replicated data types (CRDTs)

For these advanced cases, implement custom conflict resolution in your Supabase Edge Functions or trigger logic.

---

## 5. Sync Streams Configuration

Sync Streams are defined in a YAML file deployed to the PowerSync instance (via the PowerSync Dashboard for cloud, or `config.yaml` for self-hosted). Construculator uses `edition: 3`, which is the current recommended version.

> **Why edition: 3?**
> Edition 3 (Sync Streams) is the modern recommended approach as of 2025. It replaces the legacy "Sync Rules" format (edition 1/2). Key improvements: JOIN support in queries, CTE-based authorization, on-demand subscriptions with parameters, and TTL-based caching. PowerSync explicitly recommends Sync Streams for all new projects.

### Our Stream Configuration

Below is our production stream configuration, covering the four core data entities.

> **Do tables sync automatically?**
> **No.** Each table that needs to sync must be **explicitly defined** in a stream query. PowerSync does not automatically sync all tables — only tables referenced in the `SELECT` statements within stream queries will be replicated to client devices.
>
> This is by design: it provides fine-grained control over what data each user receives, based on authorization logic (CTEs) and subscription parameters.
>
> **Key point:** If a table is not mentioned in any stream query's `SELECT` statement, it will not be synced to devices at all.

```yaml
config:
  edition: 3

streams:

  # ── 1. USER PROFILE ─────────────────────────────────────────────
  # auto_subscribe: syncs immediately on connect.
  # No CTE needed — simple single-table filter by JWT user ID.
  my_user:
    auto_subscribe: true
    query: |
      SELECT id, email, first_name, last_name,
             professional_role, user_status,
             user_preferences, country_code,
             created_at, updated_at
      FROM users
      WHERE credential_id = auth.user_id()

  # ── 2. USER'S PROJECTS ──────────────────────────────────────────
  # auto_subscribe: always available offline.
  # CTE (with block) handles the JOIN-based access check.
  # The main query then filters using that CTE result.
  user_projects:
    auto_subscribe: true
    with:
      accessible_projects: |
        SELECT p.id FROM projects p
        INNER JOIN project_members pm ON p.id = pm.project_id
        INNER JOIN users u ON pm.user_id = u.id
        WHERE u.credential_id = auth.user_id()
          AND pm.membership_status = 'joined'
          AND p.project_status != 'archived'
    query: |
      SELECT id, project_name, description,
             creator_user_id, project_status,
             created_at, updated_at
      FROM projects
      WHERE id IN accessible_projects

  # ── 3. PROJECT MEMBERSHIPS ──────────────────────────────────────
  # auto_subscribe: needed for role/permission checks in the app.
  # Simple subquery — no CTE required.
  user_memberships:
    auto_subscribe: true
    query: |
      SELECT id, project_id, user_id, role_id,
             joined_at, membership_status
      FROM project_members
      WHERE user_id = (
        SELECT id FROM users
        WHERE credential_id = auth.user_id()
      )

  # ── 4. COST ESTIMATE DATA (ON-DEMAND) ────────────────────────────────────
  # NOT auto-subscribed — client subscribes when user opens a project.
  # subscription.parameter('project_id') is passed by the client.
  # CTE ensures user can only access projects they are a member of.
  # Two queries in one stream = one subscription manages both tables.
  project_cost_data:
    with:
      accessible_projects: |
        SELECT p.id FROM projects p
        INNER JOIN project_members pm ON p.id = pm.project_id
        INNER JOIN users u ON pm.user_id = u.id
        WHERE u.credential_id = auth.user_id()
          AND pm.membership_status = 'joined'
          AND p.project_status != 'archived'
      # CTE name intentionally matches the logical concept (project estimates)
      # while reading from the physical table (cost_estimates).
      # In queries below, "FROM project_estimates" reads from this CTE,
      # not directly from the database table.
      project_estimates: |
        SELECT * FROM cost_estimates
        WHERE project_id = subscription.parameter('project_id')
          AND project_id IN accessible_projects
    queries:
      - |
        SELECT id, project_id, estimate_name,
               total_cost, is_locked, locked_by_user_id,
               locked_at, created_at, updated_at
        FROM project_estimates
      - |
        SELECT ci.id, ci.estimate_id, ci.item_type,
               ci.item_name, ci.unit_price, ci.quantity,
               ci.item_total_cost, ci.currency,
               ci.created_at, ci.updated_at
        FROM cost_items ci
        WHERE ci.estimate_id IN (
          SELECT id FROM project_estimates
        )
```

> **Note on CTE naming:** The `project_estimates` CTE is named to represent the logical concept (project-scoped estimates) rather than mirroring the database table name (`cost_estimates`). In the `queries:` block that follows, `FROM project_estimates` reads from this CTE — not directly from the `cost_estimates` table. This is intentional: the CTE is where the authorization filter (`accessible_projects`) and parameter scoping (`project_id`) are applied.

### Key Design Decisions

**Authorization lives in the CTE, not the parameters**
The `with` block is server-side and cannot be tampered with by the client. Subscription parameters (like `project_id`) are just values — they scope what is returned, but the CTE enforces that the user can only access projects they are a member of. This is the correct security boundary.

**Cost Estimate Data is on-demand, not auto-subscribed**
Syncing all cost estimates and items for all projects upfront would be wasteful — a user might be in 20 projects but only work on one at a time. The `project_cost_data` stream only syncs when the app explicitly subscribes with a `project_id`. This reduces initial sync time and storage on the device.

**Two queries in one stream**
`cost_estimates` and `cost_items` are in the same stream (using `queries:` instead of `query:`). This means the client manages one subscription and both tables sync together atomically — estimates and their items are always consistent.

---

## 6. Flutter SDK Integration

The PowerSync Flutter SDK wraps a local SQLite database and handles sync in the background. App code interacts entirely with the local DB — the SDK takes care of the rest.

### Installation

```bash
flutter pub add powersync
```

### Step 1 — Define the Client-Side Schema

The schema tells PowerSync what tables and columns to materialize in the local SQLite database. It mirrors the Sync Streams config.

> **Note:** PowerSync automatically creates an `id` column of type `text` — it should not be declared explicitly.

```dart
// lib/models/schema.dart
const schema = Schema([
  Table('projects', [
    Column.text('project_name'),
    Column.text('description'),
    Column.text('creator_user_id'),
    Column.text('project_status'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  Table('cost_estimates', [
    Column.text('project_id'),
    Column.text('estimate_name'),
    Column.real('total_cost'),
    Column.integer('is_locked'),
    Column.text('locked_by_user_id'),
    Column.text('updated_at'),
  ], indexes: [
    Index('by_project', [IndexedColumn('project_id')])
  ]),
  Table('cost_items', [
    Column.text('estimate_id'),
    Column.text('item_name'),
    Column.real('unit_price'),
    Column.real('quantity'),
    Column.real('item_total_cost'),
    Column.text('updated_at'),
  ], indexes: [
    Index('by_estimate', [IndexedColumn('estimate_id')])
  ]),
]);
```

### Step 2 — Backend Connector

The connector does two things: provides the JWT to PowerSync (`fetchCredentials`), and uploads local mutations to Supabase (`uploadData`).

```dart
class SupabaseConnector extends PowerSyncBackendConnector {

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = supabase.auth.currentSession;
    if (session == null) return null;
    final powerSyncUrl = appBootstrap.envLoader.get('POWERSYNC_URL')??'';
    return PowerSyncCredentials(
      endpoint: powerSyncURL,
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase db) async {
    final tx = await db.getNextCrudTransaction();
    if (tx == null) return;
    try {
      for (final op in tx.crud) {
        switch (op.op) {
          case UpdateType.put:
            await supabase.from(op.table).upsert(op.opData!);
          case UpdateType.patch:
            await supabase.from(op.table).update(op.opData!).eq('id', op.id);
          case UpdateType.delete:
            await supabase.from(op.table).delete().eq('id', op.id);
        }
      }
      await tx.complete();
    } catch (e) {
      // Differentiate between permanent and transient failures
      if (e is PostgrestException && e.code == '42501') {
        // RLS denial (42501) — permanent failure, do not retry.
        // Mark the transaction complete so the queue can advance.
        // The local optimistic change persists; surface a conflict
        // message to the user via a separate error state.
        await tx.complete();
        // TODO: [CA-660] Emit conflict event to UI layer when RLS denial is detected.
        // https://ripplearc.youtrack.cloud/issue/CA-660
        return;
      }
      // Transient failure (network timeout, server error, etc.) —
      // rethrow so PowerSync retries automatically
      rethrow;
    }
  }
}
```

### Step 3 — Reading Data

Use `getAll()` for lists, `getOptional()` for single rows, and `watch()` for reactive UI queries that update automatically when data changes.

```dart
// One-time query
final projects = await db.getAll(
  'SELECT * FROM projects WHERE project_status != ?', ['archived']
);

// Reactive query — rebuilds widget when data changes
StreamBuilder(
  stream: db.watch(
    'SELECT * FROM cost_estimates WHERE project_id = ?', [projectId]
  ),
  builder: (context, snapshot) {
    final estimates = snapshot.data ?? [];
    return EstimatesList(estimates: estimates);
  },
)
```

### Step 4 — Writing Data

Writes go to local SQLite instantly. PowerSync queues and uploads them to Supabase in the background.

```dart
// Create a new cost estimate
await db.execute(
  '''INSERT INTO cost_estimates
     (id, project_id, estimate_name, total_cost, created_at, updated_at)
     VALUES (?, ?, ?, ?, datetime(), datetime())''',
  [uuid(), projectId, name, 0.0],
);

// Update an estimate
await db.execute(
  'UPDATE cost_estimates SET estimate_name = ?, updated_at = datetime() WHERE id = ?',
  [newName, estimateId],
);
```

### Step 5 — On-Demand Stream Subscription

Subscribe to the `project_cost_data` stream when the user opens a project. Unsubscribe when they navigate away. PowerSync keeps the data cached locally for 24 hours by default (TTL), so re-opening the same project is instant.

```dart
// When user opens a project
final sub = await db
  .syncStream('project_cost_data', {'project_id': projectId})
  .subscribe();

await sub.waitForFirstSync(); // Wait for initial data

// Now query locally as normal
final estimates = await db.getAll(
  'SELECT * FROM cost_estimates WHERE project_id = ?', [projectId]
);

// When user navigates away
sub.unsubscribe();
```

**What happens after the 24-hour TTL expires?**

After 24 hours of inactivity (no active subscription to a stream with specific parameters):

1. **Data is removed from local storage** — PowerSync deletes the cached data for that subscription to free up space
2. **On next access** — When the user reopens the same project, PowerSync re-fetches the data from the server (requires network)
3. **TTL resets** — The 24-hour timer restarts each time the stream is actively subscribed

**Important:**
- The TTL only applies to **on-demand streams** (like `project_cost_data`), not `auto_subscribe` streams (like `user_projects`)
- Auto-subscribed streams remain cached indefinitely as long as the user is authenticated
- You can configure custom TTL values in the stream definition if 24 hours doesn't fit your use case

---

## 7. Security Model

PowerSync and Supabase handle security at different layers. Both are required — they are complementary, not redundant.

| | Supabase RLS | PowerSync Streams |
|---|---|---|
| **Protects** | Server-side API reads/writes | What data lands on each device |
| **Triggered by** | Every Postgres query | At replication time (WAL) |
| **Bypassed by** | Service role key | Nothing — it is the gate for sync |
| **Controls** | PostgREST, Edge Functions, SDKs | PowerSync replication scope |

### Authorization Rules

- **Never put authorization logic in subscription parameters** — parameters are just values from the client and cannot be trusted for access control.
- **All access control logic goes in the `with` (CTE) block** — joins to `project_members`, `membership_status` checks, and `auth.user_id()` comparisons happen here.
- **`auth.user_id()` is signed as part of the JWT** and is safe to use for filtering — the client cannot forge it.
- **`subscription.parameter()` is client-supplied** and should only be used to scope what data is returned, never to grant access.

### JWT Validation

PowerSync validates JWTs using Supabase's JWKS endpoint. This uses asymmetric key signing — Supabase holds the private key, PowerSync only needs the public key to verify tokens.

```yaml
# In PowerSync config
client_auth:
  jwks_uri: https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
  audience: ["authenticated"]
```

### Using JWT Custom Claims for Authorization

> **Important for Construculator:** If using the JWT-based permissions approach (PR #25), the JWT will contain custom `app_metadata` with project permissions:

```json
{
  "app_metadata": {
    "projects": {
      "950e8400-e29b-41d4-a716-446655440001": [
        "add_cost_estimation",
        "delete_cost_estimation",
        "edit_cost_estimation",
        "get_cost_estimations",
        "lock_cost_estimation",
        "view_project"
      ],
      "950e8400-e29b-41d4-a716-446655440002": [
        "view_project",
        "get_cost_estimations"
      ]
    }
  }
}
```

PowerSync Edition 3 supports reading JWT claims directly in stream queries using `auth.jwt_claim()`:

```yaml
# Example: Using JWT claims instead of database queries for authorization
user_projects:
  auto_subscribe: true
  query: |
    SELECT id, project_name, description,
           creator_user_id, project_status,
           created_at, updated_at
    FROM projects
    WHERE id IN (
      SELECT jsonb_object_keys(
        auth.jwt_claim('app_metadata.projects')::jsonb
      )::uuid
    )
```

**Key Points:**
- `auth.jwt_claim('app_metadata.projects')` reads the custom claim from the JWT
- The JSONB `?` operator checks if a key exists in the JSON object (e.g., checking if a specific project_id exists in the user's projects)
- `jsonb_object_keys()` extracts all keys (project IDs) from the projects object as a set of text values
- This eliminates the need for `JOIN` with `project_members` if all authorization data is in the JWT
- The JWT is cryptographically signed by Supabase — PowerSync trusts it after validation
- When permissions change, the client must call `refreshSession()` to get updated claims

**When to use JWT claims vs database queries:**
- **JWT claims**: Faster, no database joins needed. Best when permissions are cached in the token (see JWT Auth documentation).
- **Database queries**: Always up-to-date, no token refresh needed. Better for frequently changing permissions.

For Construculator, if implementing PR #25 (JWT Project Claims), use JWT-based authorization. Otherwise, stick with the database query approach shown in Section 4.

> ⚠️ **Cost estimate locking**
> The `is_locked`, `locked_by_user_id`, and `locked_at` fields are server-authoritative. PowerSync syncs them down to all clients. The app must check `is_locked` before showing edit UI. If a user edits offline while another user locks the estimate, the upload will be rejected by Supabase RLS on the next sync — the app should handle this gracefully by showing a conflict message.

---

## 8. Local Development & Deployment

### Local Stack

For local development, PowerSync runs as a Docker container alongside your local Supabase instance. Supabase must be started first, as PowerSync needs to connect to it on startup.
```bash
# 1. Start local Supabase
npx supabase start

# 2. Generate signing keys (first time only)
npx supabase gen signing-key

# 3. Start PowerSync
docker compose --file ./powersync/compose.yaml --env-file .env.local up -d
```

### File Structure

The PowerSync config lives in a `powersync/` directory at the root of the project. There are two config files — a main service config and a separate sync streams file. Keeping them separate is the recommended approach as it keeps the main config clean.
```
construculator-backend/
├── powersync/
│   ├── compose.yaml          # Docker Compose — starts the PowerSync container
│   ├── powersync.yaml        # Main service config (replication, auth, storage, port)
│   └── sync-config.yaml      # Sync Streams definition (edition: 3, streams: ...)
├── .env.local                # Environment variables
└── supabase/
    └── signing_keys.json     # Generated by: supabase gen signing-key
```

### powersync/compose.yaml
```yaml
# Supabase must be running before starting this.
# Start it with: supabase start

services:
  powersync:
    container_name: powersync_demo
    restart: unless-stopped
    env_file:
      - ../.env.local
    image: journeyapps/powersync-service:latest
    volumes:
      - ./powersync.yaml:/app/powersync.yaml        # main service config
      - ./sync-config.yaml:/app/sync-config.yaml    # sync streams definition
    networks:
      - supabase_network_powersync
    ports:
      - ${PS_PORT}:${PS_PORT}

networks:
  supabase_network_powersync:
    external: true  # created automatically by Supabase local
```

> **Why `external: true`?** When running `supabase start`, Supabase creates a Docker network automatically. PowerSync needs to join this same network to reach Supabase Kong (the local API gateway) and Postgres. The exact network name can be found via `docker network ls`.

### powersync/powersync.yaml

The main service config. Handles replication, storage, auth, port — and references `sync-config.yaml` via `sync_config: path:`.
```yaml
replication:
  connections:
    - type: postgresql
      uri: !env PS_POSTGRESQL_URI
      sslmode: disable  # use 'require' in production

storage:
  type: postgresql
  uri: !env PS_POSTGRESQL_URI

port: !env PS_PORT

client_auth:
  jwks_uri: !env PS_BACKEND_JWKS_URI
  audience: ["authenticated"]

api:
  tokens:
    - !env PS_API_TOKEN

# Reference the separate streams file (recommended approach)
sync_config:
  path: /app/sync-config.yaml
```

> **Inline alternative:** Streams can also be embedded directly in this file using `sync_config: content: |` followed by indented YAML. However, this approach gets messy for large configs — the separate file approach is cleaner.

### powersync/sync-config.yaml

This is where the Sync Streams are defined. It is mounted into the container and referenced by `powersync.yaml`. When updating streams, only this file needs to be modified.
```yaml
config:
  edition: 3

streams:
  my_user:
    auto_subscribe: true
    query: |
      SELECT id, email, first_name, last_name, ...
      FROM users
      WHERE credential_id = auth.user_id()

  # ... rest of the streams (see Section 4)
```

### Environment Variables (.env.local)

| Variable | Purpose |
|---|---|
| `PS_POSTGRESQL_URI` | Postgres connection string for replication and bucket storage |
| `PS_PORT` | Port for the PowerSync service (e.g. `8080`) |
| `PS_BACKEND_JWKS_URI` | Supabase JWKS endpoint for JWT validation |
| `PS_API_TOKEN` | Admin token for PowerSync API/dashboard access |
```dotenv
# Example .env.local
PS_POSTGRESQL_URI=postgresql://postgres:postgres@supabase_db:5432/postgres
PS_PORT=8080
PS_BACKEND_JWKS_URI=http://supabase_kong:8000/auth/v1/.well-known/jwks.json
PS_API_TOKEN=replace-with-long-random-token
```

### JWKS URI by Environment

The JWKS URI tells PowerSync where to fetch Supabase's public signing keys to validate JWTs. The right value depends on where the request is coming from:
```bash
# Inside Docker network — use this in .env.local for the PowerSync container
PS_BACKEND_JWKS_URI=http://supabase_kong:8000/auth/v1/.well-known/jwks.json

# From your host machine — use this for manual testing via curl
PS_BACKEND_JWKS_URI=http://localhost:54321/auth/v1/.well-known/jwks.json

# Supabase Cloud (production)
PS_BACKEND_JWKS_URI=https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
```

Verify the endpoint is working: `curl <PS_BACKEND_JWKS_URI>` should return a JSON response with a non-empty `keys` array. An empty array means signing keys haven't been generated yet — run `supabase gen signing-key`.

### Production Checklist

- Set `sslmode=require` on the PostgreSQL URI — never disable SSL on public networks
- Use dedicated DB credentials with least-privilege grants for the PowerSync replication user
- Pin the Docker image version (replace `:latest` with a specific tag) for controlled rollouts
- Use separate connection URIs for replication source vs bucket storage at scale
- Keep JWT audience strict and environment-specific
- Never include service-role secrets in the Flutter app

---

## 9. Pricing & Infrastructure

| Users | Supabase (DB + Auth) | PowerSync Managed | PowerSync Self-Hosted |
|---|---|---|---|
| **10k MAU** | $0 (Free tier) | $0 – $112/mo | $60 – $70/mo |
| **100k MAU** | $25 – $33/mo | $490 – $1,120/mo | $120 – $130/mo |
| **1M MAU** | $2,905 – $3,230/mo | $4,900 – $11,200/mo | $240 – $250/mo |

### Supabase

- **10k MAU:** Free tier covers up to 50k MAU — no cost.
- **100k MAU:** Pro plan at $25/mo base, plus $0.00325 per MAU over 100k. With a 20k buffer: ~$33/mo.
- **1M MAU:** Pro plan base $25/mo + 900k extra MAU at $0.00325 = ~$2,905 – $3,230/mo.

### PowerSync Managed (Cloud)

PowerSync Cloud pricing is based on sync operations per month. Using an estimate of ~1,000 operations per user per month:

- **10k MAU:** ~$50/mo typical, up to $112/mo at peak. Free tier may cover low-usage scenarios.
- **100k MAU:** ~$490 – $1,120/mo depending on operation volume.
- **1M MAU:** ~$4,900 – $11,200/mo. At this scale, self-hosting becomes significantly more cost-effective.

### PowerSync Self-Hosted (AWS EC2)

Self-hosted PowerSync runs as a single Docker service. EC2 instance sizing by load:

- **10k MAU:** t3.large (2 vCPU, 8GB RAM) + S3 backup storage ≈ $60 – $70/mo.
- **100k MAU:** t3.xlarge (4 vCPU, 16GB RAM) + storage ≈ $120 – $130/mo.
- **1M MAU:** t3.2xlarge (8 vCPU, 32GB RAM) + storage ≈ $240 – $250/mo.

> ✅ **Recommendation:** For early-stage and up to ~100k MAU, PowerSync Cloud (managed) is the pragmatic choice — it eliminates ops overhead entirely. Self-hosting becomes compelling at 1M+ MAU where the cost difference is significant ($240/mo vs $4,900+/mo). Start managed, migrate if needed.

---

## 10. Migration Guide to JWT-Based Authorization

If implementing the JWT custom claims approach for permissions, the PowerSync stream configuration needs to be updated to use `auth.jwt_claim()` instead of database queries.

#### Step 1: Verify JWT Claims Structure

After deploying the custom access token hook (from PR #25), verify the JWT contains the expected structure:

```bash
# Decode a user's JWT to inspect claims
# Use jwt.io or run this in your app after login:
console.log(supabase.auth.currentUser?.appMetadata);
```

Expected output:
```json
{
  "projects": {
    "project-uuid-1": ["permission1", "permission2", ...],
    "project-uuid-2": ["permission1", ...]
  }
}
```

#### Step 2: Update Stream Configuration

**Before (Database Query Approach):**
```yaml
user_projects:
  auto_subscribe: true
  with:
    accessible_projects: |
      SELECT p.id FROM projects p
      INNER JOIN project_members pm ON p.id = pm.project_id
      INNER JOIN users u ON pm.user_id = u.id
      WHERE u.credential_id = auth.user_id()
        AND pm.membership_status = 'joined'
        AND p.project_status != 'archived'
  query: |
    SELECT id, project_name, description,
           creator_user_id, project_status,
           created_at, updated_at
    FROM projects
    WHERE id IN accessible_projects
```

**After (JWT Claims Approach):**
```yaml
user_projects:
  auto_subscribe: true
  query: |
    SELECT id, project_name, description,
           creator_user_id, project_status,
           created_at, updated_at
    FROM projects
    WHERE id IN (
      SELECT jsonb_object_keys(
        auth.jwt_claim('app_metadata.projects')::jsonb
      )::uuid
    )
    AND project_status != 'archived'
```

#### Step 3: Update Cost Estimate Stream (On-Demand)

**Before:**
```yaml
project_cost_data:
  with:
    accessible_projects: |
      SELECT p.id FROM projects p
      INNER JOIN project_members pm ON p.id = pm.project_id
      INNER JOIN users u ON pm.user_id = u.id
      WHERE u.credential_id = auth.user_id()
        AND pm.membership_status = 'joined'
    project_estimates: |
      SELECT * FROM cost_estimates
      WHERE project_id = subscription.parameter('project_id')
        AND project_id IN accessible_projects
  queries:
    - |
      SELECT ... FROM project_estimates
    - |
      SELECT ... FROM cost_items WHERE ...
```

**After:**
```yaml
project_cost_data:
  with:
    project_estimates: |
      SELECT * FROM cost_estimates
      WHERE project_id = subscription.parameter('project_id')
        AND (auth.jwt_claim('app_metadata.projects')::jsonb) ? (subscription.parameter('project_id')::text)
  queries:
    - |
      SELECT id, project_id, estimate_name,
             total_cost, is_locked, locked_by_user_id,
             locked_at, created_at, updated_at
      FROM project_estimates
    - |
      SELECT ci.id, ci.estimate_id, ci.item_type,
             ci.item_name, ci.unit_price, ci.quantity,
             ci.item_total_cost, ci.currency,
             ci.created_at, ci.updated_at
      FROM cost_items ci
      WHERE ci.estimate_id IN (
        SELECT id FROM project_estimates
      )
```

#### Step 4: Deploy and Test

1. **Update sync-config.yaml** with the new stream definitions
2. **Restart PowerSync service:**
   ```bash
   docker compose --file ./powersync/compose.yaml restart
   ```
3. **Test in the app:**
   - Sign in with a test user
   - Verify projects sync correctly
   - Check that permission changes require `refreshSession()`
   - Handle `refreshSession()` failures gracefully (offline or auth errors)
   - Verify that stale permissions don't grant unauthorized access server-side (RLS still enforces)

#### Step 5: Performance Comparison

The JWT-based approach should show:
- **Faster sync initialization** — no `project_members` joins
- **Reduced database load** — PowerSync doesn't query membership table
- **Same data synced** — users still see only their authorized projects

Monitor PowerSync logs for any authorization failures:
```bash
docker logs powersync_demo --follow
```

### Rollback Plan

If issues arise, revert `sync-config.yaml` to the database query approach and restart PowerSync. No data migration needed — this is configuration-only.

### Migration Checklist

- [ ] Custom access token hook deployed (PR #25)
- [ ] JWT claims verified via jwt.io or app inspection
- [ ] sync-config.yaml updated with JWT-based queries
- [ ] PowerSync service restarted
- [ ] App tested: projects sync correctly
- [ ] App tested: `refreshSession()` updates permissions
- [ ] App tested: offline behavior when JWT refresh fails
- [ ] App tested: RLS still enforces permissions server-side
- [ ] Performance verified: faster sync, lower DB load
- [ ] Rollback plan documented and tested in staging

### PowerSync vs Pure Supabase Toggle

**Q: Can we have a switch to control whether to use PowerSync or Pure Supabase?**

Yes, but it requires careful architectural planning. Here are the implementation approaches:

#### Approach 1: Feature Flag with Separate Data Access Layer (Recommended)

Create an abstraction layer that switches between PowerSync and Supabase client:

```dart
abstract class DataRepository {
  Future<List<Project>> getProjects();
  Future<void> updateProject(String id, Map<String, dynamic> data);
  Stream<List<Project>> watchProjects();
}

class PowerSyncRepository implements DataRepository {
  final PowerSyncDatabase db;

  @override
  Future<List<Project>> getProjects() async {
    return await db.getAll('SELECT * FROM projects');
  }

  @override
  Stream<List<Project>> watchProjects() {
    return db.watch('SELECT * FROM projects');
  }
}

class SupabaseRepository implements DataRepository {
  final SupabaseClient client;

  @override
  Future<List<Project>> getProjects() async {
    return await client.from('projects').select();
  }

  @override
  Stream<List<Project>> watchProjects() {
    return client.from('projects').stream(primaryKey: ['id']);
  }
}

// In your app initialization
final bool usePowerSync = FeatureFlags.offlineMode; // from remote config
final DataRepository repo = usePowerSync
    ? PowerSyncRepository(powerSyncDb)
    : SupabaseRepository(supabase);
```

**Pros:**
- Clean separation of concerns
- Easy to test both modes
- Can enable PowerSync per-user via feature flags
- Allows gradual rollout

**Cons:**
- Requires maintaining two code paths
- Some PowerSync features (offline queuing, conflict resolution) don't apply to pure Supabase mode
- Schema changes must be tested in both modes

#### Approach 2: PowerSync-Only with Disabled Sync (Not Recommended)

Technically, you could use PowerSync in "direct mode" (queries go straight to Supabase), but this defeats the purpose of PowerSync and adds unnecessary complexity.

#### Recommended Strategy for Construculator

1. **Default to PowerSync for production** — construction sites need offline-first capabilities
2. **Use feature flags for testing** — enable pure Supabase mode for QA environments or specific test users
3. **Abstract data access early** — implement the repository pattern from the start to avoid tight coupling
4. **Monitor performance** — use analytics to compare sync performance vs direct Supabase queries

**When to use each mode:**

| Use Case | Mode | Reason |
|---|---|---|
| Production mobile app | PowerSync | Offline-first, handles poor connectivity |
| Admin web dashboard | Pure Supabase | Always online, simpler implementation |
| Automated testing | Pure Supabase | Faster, no sync delays |
| Development | Toggle via feature flag | Test both paths |

**Implementation Checklist:**

- [ ] Define `DataRepository` interface covering all data operations
- [ ] Implement `PowerSyncRepository` using PowerSync SDK
- [ ] Implement `SupabaseRepository` using Supabase client
- [ ] Add feature flag (e.g., `USE_OFFLINE_SYNC`) to remote config
- [ ] Initialize appropriate repository based on flag
- [ ] Test both code paths in CI/CD pipeline
- [ ] Document which features are PowerSync-only (offline queue, conflict UI)

---

## 11. Common Pitfalls

### No data syncing to client

- Check that the user's `membership_status` is `'joined'`, not `'invited'`. The CTE filters on this.
- Verify `auth.user_id()` matches the `credential_id` column in the `users` table. If the Supabase JWT `sub` claim does not match `credential_id`, the CTE returns zero rows.
- Test the CTE query manually in psql with a real `user_id` to confirm it returns results.

### JWKS endpoint returns empty keys

- Run `npx supabase gen signing-key`.
- Save the generated key to `supabase/signing_keys.json`
- Update `supabase/config.toml` with the new keys path
- Restart Supabase services after generating keys.
- Run `curl <PS_BACKEND_JWKS_URI>` and confirm the `keys` array is non-empty.

### Upload queue stuck

- An RLS violation on Supabase will cause a fatal upload error — PowerSync stops retrying. Check Supabase logs for `permission denied` errors.


### Works locally but not on Supabase Cloud

- Ensure `PS_POSTGRESQL_URI` uses `sslmode=require` for Supabase Cloud (not `sslmode=disable`).
- Verify all environment variables (`PS_API_TOKEN`, `PS_BACKEND_JWKS_URI`) are correctly set in production config.
- Check that the PowerSync service can reach the Supabase JWKS URL — firewall or VPN rules may block it.

### JWT claims not working in stream queries

- Verify `auth.jwt_claim()` path uses dot notation: `'app_metadata.projects'` not `['app_metadata']['projects']`
- When using JSONB operators like `?`, ensure values are explicitly cast: `subscription.parameter('project_id')::text`
- Check JWT contains expected claims by decoding it at jwt.io
- Ensure custom access token hook is deployed and users have refreshed their sessions

---

*PowerSync Integration Wiki · [docs.powersync.com](https://docs.powersync.com)*
