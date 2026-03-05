# PowerSync Integration Wiki
**Construculator · Offline-First Architecture · PowerSync + Supabase + Flutter**

---

## Table of Contents
1. [What is PowerSync?](#1-what-is-powersync)
2. [Core Concepts](#2-core-concepts)
3. [How PowerSync Works with Supabase](#3-how-powersync-works-with-supabase)
4. [Sync Streams Configuration](#4-sync-streams-configuration)
5. [Flutter SDK Integration](#5-flutter-sdk-integration)
6. [Security Model](#6-security-model)
7. [Local Development & Deployment](#7-local-development--deployment)
8. [Pricing & Infrastructure](#8-pricing--infrastructure)
9. [Common Pitfalls](#9-common-pitfalls)

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

## 3. How PowerSync Works with Supabase

### Authentication Flow

PowerSync does not have its own auth — it delegates entirely to Supabase Auth via JWT validation.

![Authentication Flow](https://mermaid.ink/svg/pako:eNptk9tq20AQhl9lmKsWFKOT1XgvAiVNLtIWTJU2UAxlvRrLi6VddQ8krvG7d1eJRZNauljN_N8cJR1Q6IaQIVj67UkJ-iR5a3i_UjBeAzdOCjlw5eC7JXPO_3EYgFu47bxzZKJ5lvJuG7HaD3zNLY2Oc-CyjthSP5Kp90qcQ-4ePo_QeN6oZtBSuZU6obHRi6ur0AiDL7qVkxA80R8KM6hlq0AqMHFw6yYkiBPzg3ey4Y5AGGpIOck7-wo8Vbl7uId3XAiy9l7vSL1fvam5rBlca6VIOHiUYRMh4kQs6wDEURjckhNbGPy6kwJ2tJ-qRfniJc83ct6oV_KYImpTx2_zR_HmyRkeGvBhP79kAxuje7B-_R8Yeu72YJ0h3kNYj5H0b6nT1PUzENPB2osdOYsJtkY2yJzxlGBPpufRxEOMX6HbUk8rZOEx3OoY-PBGf2rdn0KM9u0W2SasOlh-iNO8fJQTQqohc629csiKqhpzIDvgE7K8yGdpkVdFtpgXl3m1uExwjywry1lWzvNFVn0o07Sqjgn-Gaums8Cli7xclGkWznmRIDXSafP1-dcQWm1ki8e_51X79Q)

### Data Flow: Reads

All reads in the Flutter app come from the local SQLite database, not from Supabase directly (unless an online-first fetch is explicitly needed). This is what makes the app instant and offline-capable.

![Read Flow](https://mermaid.ink/svg/pako:eNptklFvmzAQx7-Kdc80BRIC-KFSVFhULatYyTRp4sWFK7EKNjN2uyzKd58hJWuk-Ml3_5__5zv7AKWsECj0-NugKDHhrFasLQQZV8eU5iXvmNAkWxPWk9x07Jn1SDLZ61phfxXNBzST76jyvSivIXny9YIZEle57xuucUA3smTNR3yNXHXdgH1pjNaohrAQE5etb-7usjUlD495-rS9_ZElq216m6SbdJteQjklP1cbgm8o9FnJPxRr2uxJrxWyltiJKf5_AGcoQVu_5QKJ6e1Fnk35ivoSs81Skp9sKmw0m1QrDPLY5FSu3DFRD3UmyKY_Qblt4n473mZ_thm1G0tZlpIn1EYJouT7J5dHaecq306jcia3B9FrO02nEOBArXgFVCuDDrS2JzaEcBgcCtA7bLEAareVei2gEEd7xD7FLynb6ZSSpt4BfWFNbyPTVUxPf-ycVSgqVPfSCA3U88PRBOgB_gBduMEsir3Ai4J4EfhLP3BgD9R3lzMvcGN36UeLuTf3oqMDf8e67iwI_NCbB6Efh1EczhcOYMW1VN9OX72U4oXXcPwHIqfsPw)

### Data Flow: Writes

Writes go to the local SQLite database first (optimistic), then get uploaded to Supabase via the backend connector. PowerSync queues writes and retries automatically on failure.

![Write Flow](https://mermaid.ink/svg/pako:eNptk11v2jAUhv-K5atWShEhgRBfVELQoalsoou2SVNujHMarCZ25o-1HeK_zw4xaBu-SXze55zz-uuAmawAE6zhpwXBYMVprWhbCtSPjirDGe-oMOirBnUtvug6RDX60FhjQPnpNap42nADHtxIRpthfpVcPXpsK19BFe-C-cA1bimF8KD_AjPyqrnt2iOF7eiOanBFtakV6FIE2K_q7v7euSbooeIGVdTQILqo005WCap2I3gDZg3c3AbipN2FCoVlDLRGN1xo4_rfXhoNpCu3eiRoSTtjFSC2p6I-b4OTAvBkwQKyXSNp9bfs10sGZeXMXsx4xQHbNUGL7Uek_JlqE9TtetC-0Ya7VQL6siku_mhjgv0QGrLOnqV45qqF6h99kL8vNkj789pR9hIQaHTfB61A8P8yQ-qDUpfj8-OzdPbkr9N1inqm2MtXxJyFhrPzmkBUOMK14hUmRlmIcAuqpX6KDx4qsdlDCyUm7rdSLyUuxdGluMvxQ8o2ZClp6z0mz9TZjbDt_PYMT-EcVa4ZqKW0wmAymUz6Ipgc8BsmyXQ2ypLpOEmmcZbO43gW4XdM4iQfzbN8Ps_jdJblSZ4dI_y77zseZXGSZsl4PI0naZaleYTB3T-pPp1eZP8wj38AVIoY0w)

> ✅ **Supabase is still the source of truth.** PowerSync is a sync layer, not a database replacement. All business logic, validation, and authorization for writes still runs on Supabase (via RLS, triggers, and edge functions). PowerSync just ensures the results of those writes get propagated back to all relevant devices.

---

## 4. Sync Streams Configuration

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

### Key Design Decisions

**Authorization lives in the CTE, not the parameters**
The `with` block is server-side and cannot be tampered with by the client. Subscription parameters (like `project_id`) are just values — they scope what is returned, but the CTE enforces that the user can only access projects they are a member of. This is the correct security boundary.

**Cost Estimate Data is on-demand, not auto-subscribed**
Syncing all cost estimates and items for all projects upfront would be wasteful — a user might be in 20 projects but only work on one at a time. The `project_cost_data` stream only syncs when the app explicitly subscribes with a `project_id`. This reduces initial sync time and storage on the device.

**Two queries in one stream**
`cost_estimates` and `cost_items` are in the same stream (using `queries:` instead of `query:`). This means the client manages one subscription and both tables sync together atomically — estimates and their items are always consistent.

---

## 5. Flutter SDK Integration

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
    Column.text('project_status'),
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
    return PowerSyncCredentials(
      endpoint: Env.powerSyncUrl,
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
      // PowerSync retries automatically on failure
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

---

## 6. Security Model

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

> ⚠️ **Cost estimate locking**
> The `is_locked`, `locked_by_user_id`, and `locked_at` fields are server-authoritative. PowerSync syncs them down to all clients. The app must check `is_locked` before showing edit UI. If a user edits offline while another user locks the estimate, the upload will be rejected by Supabase RLS on the next sync — the app should handle this gracefully by showing a conflict message.

---

## 7. Local Development & Deployment

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

## 8. Pricing & Infrastructure

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

## 9. Common Pitfalls

### No data syncing to client

- Check that the user's `membership_status` is `'joined'`, not `'invited'`. The CTE filters on this.
- Verify `auth.user_id()` matches the `credential_id` column in the `users` table. If the Supabase JWT `sub` claim does not match `credential_id`, the CTE returns zero rows.
- Test the CTE query manually in psql with a real `user_id` to confirm it returns results.

### JWKS endpoint returns empty keys

- Run `npx supabase gen signing-key`.
- Save the generated key to supabase/signing_key.json
- Update supabase/config.toml with the new keys path
- Restart Supabase services after generating keys.
- Run `curl <PS_BACKEND_JWKS_URI>` and confirm the `keys` array is non-empty.

### Upload queue stuck

- An RLS violation on Supabase will cause a fatal upload error — PowerSync stops retrying. Check Supabase logs for `permission denied` errors.


### Works locally but not on Supabase Cloud

- Ensure `PS_POSTGRESQL_URI` uses `sslmode=require` for Supabase Cloud (not `sslmode=disable`).
- Verify all environment variables (`PS_API_TOKEN`, `PS_BACKEND_JWKS_URI`) are correctly set in production config.
- Check that the PowerSync service can reach the Supabase JWKS URL — firewall or VPN rules may block it.

---

*PowerSync Integration Wiki · [docs.powersync.com](https://docs.powersync.com)*
