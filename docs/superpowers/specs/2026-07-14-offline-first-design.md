# BugHive Offline-First — Design Spec

**Date:** 2026-07-14
**Status:** Approved (design), pending implementation plan
**Philosophy:** _Write first, sync when you're ready._

---

## 1. Problem & Goals

After offline mode was removed (commits `cb3db34`, `be92362`), the data layer
became **online-only**: every read and write hits Supabase directly. Two
symptoms result:

1. **Stalls offline.** `HomePage` → `loadWorkspace()` → `fetchRepositories()`
   blocks with no connection. "Keep Local" throws because it does a Supabase
   INSERT over the network.
2. **Ghost duplicate logs.** `createEngineeringLog` uses `.insert()` with a
   **server-generated** id. On a connectivity blip the insert can succeed
   server-side while the client sees a timeout and retries — producing a second
   row with a *different* id. Users see 2 logs and must delete one by hand.

### Goals

- A signed-in user (who has logged in online at least once) can **open the app,
  browse cached data, and create/edit/delete logs + attach images entirely
  offline**. Nothing stalls, nothing is lost.
- Queued work **auto-syncs to Supabase** (Layer A) when connectivity returns;
  turning a log into a **GitHub Issue stays a manual, explicit action**
  (Layer B), exactly as today.
- **Sync is idempotent.** Replaying any queued operation — after a timeout,
  crash, or reconnect — never creates a duplicate row or a duplicate storage
  object. This is the primary fix for the ghost-log bug.

### Non-goals (YAGNI)

- No bidirectional conflict-resolution engine. Single user owns their own data;
  edits are **last-write-wins**.
- No offline repository add (validating a repo + importing issues needs GitHub).
- No offline GitHub issue creation/close (Layer B is online-only).
- No local full-text search or analytics.

---

## 2. Core Principle

Offline is a **transparent infrastructure layer beneath the existing single
Supabase-backed model** — not a second data path. One identity (GitHub), one set
of models, one set of controllers/pages. The cache + queue live *inside*
`SupabaseService`, so callers barely change.

This is the crucial distinction from the offline mode that was removed: that was
a **parallel no-login identity** with `local_*` IDs and a separate serializer
path ("two ways to develop"). This design has **one way**: every write goes
through the same cache→queue→drain pipeline whether online or offline.

---

## 3. Idempotency Model (the ghost-log fix)

Three mechanisms together guarantee no duplicates:

1. **Client-generated UUIDs as the real primary key.** When a log (or
   attachment) is created, the app generates its `uuid` on-device and uses it as
   the actual Supabase PK. `EngineeringLog.toSupabaseJson()` already emits `id`
   when present (`if (id != null) "id": id`), so no model change is needed.
   No `local_*` prefix, no ID reconciliation.

2. **`upsert` instead of `insert`.** Draining a `createLog`/`createAttachment`
   op uses `upsert(..., onConflict: "id")`. Replaying the same op targets the
   same id → the row is created once and thereafter no-ops/updates. Both
   `insert` and `update` privileges + RLS policies already exist, so upsert is
   permitted with no DB change.

3. **Deterministic storage paths.** An attachment's screenshot uploads to
   `logs/{logId}/{attachmentId}.png` (keyed by the attachment's UUID, not a
   timestamp) with `upsert: true`. Re-draining overwrites the same object
   instead of creating a second file.

**Single write path.** Even when online, writes go
`optimistic cache update → enqueue → trySync()`. There is no direct-insert code
path left that could double-write. A queue op is **removed only after its server
write is confirmed**; if the app dies mid-drain, replay is safe because of (1)–(3).

`sync_status` (LOCAL/SYNCED/CLOSED) remains purely about **GitHub** state.
"Pending device→cloud" is tracked separately by **queue membership**, never by
mutating `sync_status`.

---

## 4. Components

New files under `lib/app/services/offline/`.

### 4.1 `ConnectivityService`
- Wraps `connectivity_plus`. Exposes `bool get isOnline` and
  `Stream<bool> get onStatusChange` (emits on offline↔online transitions).
- A Supabase/network exception thrown mid-call is also treated as "offline" so a
  false-positive `isOnline` never blocks a write (the op just stays queued).

### 4.2 `LocalCache`
- NyStorage JSON snapshots, namespaced per `userId`:
  - `cache:repos:<uid>` → `List<Repository>`
  - `cache:logs:<uid>:<repoId>` → `List<EngineeringLog>`
  - `cache:attachments:<uid>:<logId>` → `List<Attachment>`
- Written **on every successful network read** (network-first refresh) and
  **optimistically on every write** (so the UI reflects changes instantly
  offline).
- Reuses existing `fromJson` / `toSupabaseJson` serializers.

### 4.3 `SyncQueue`
- Ordered NyStorage list (FIFO) of operations, per user:
  `{ opId, type, payloadJson, localFilePath?, createdAt, error? }`
- `type ∈ { createLog, updateLog, deleteLog, createAttachment }`.
- Helpers: `enqueue`, `peekAll`, `remove(opId)`, `markError(opId, msg)`,
  and `cancelCreateFor(logId)` (see delete-cancels-create below).
- `pendingCount` exposed as a `ValueNotifier<int>` for the UI.

### 4.4 `SyncManager`
- Subscribes to `ConnectivityService.onStatusChange`; also runs once at app
  start if online.
- On offline→online: **drain the queue FIFO**. For each op:
  - `createLog`/`updateLog` → `upsert` the row.
  - `createAttachment` → if `localFilePath` set, upload to the deterministic
    path, then `upsert` the attachment row with the resulting public URL and
    patch the cached record.
  - `deleteLog` → delete by id (idempotent; deleting a missing row is a no-op).
  - On success → `remove(opId)`. On failure → `markError` and stop that op,
    surface a retry; **never drop the op**.
- Emits drain lifecycle so the UI can show "syncing N…" / "synced".

### 4.5 `SupabaseService` (modified)
- Injected with `ConnectivityService`, `LocalCache`, `SyncQueue`.
- **Reads** (`fetchRepositories`, `fetchEngineeringLogs`, `fetchAttachments`,
  `fetchLogCounts`): if online → fetch with a **6–8s timeout**, refresh cache,
  return; if offline or on timeout/error → return from cache. **Timeout: 8s.**
- **Writes** (`createEngineeringLog`, `updateEngineeringLog`,
  `deleteEngineeringLog`, `createAttachment`, `uploadScreenshot`): assign UUID
  where needed → update cache optimistically → enqueue op → `trySync()`
  (drains immediately if online). Returns the optimistic model right away.

---

## 5. Data Flows

### 5.1 Create log + image while offline
1. `LogController.createLocalLog` → `SupabaseService.createEngineeringLog`.
2. Generate `uuid` → build log with that id, `sync_status = LOCAL`.
3. Cache upsert into `cache:logs`. Enqueue `createLog`.
4. For each picked image: copy the file into the app-documents dir
   (`path_provider`, e.g. `pending_attachments/<attachmentUuid>.png`) so it
   survives OS temp cleanup; create an `Attachment` (client UUID, `fileUrl` =
   local path placeholder); cache it; enqueue `createAttachment` with
   `localFilePath`.
5. Return immediately; page pops. Card shows **"Pending sync"**.

### 5.2 Reconnect drain (Layer A, automatic)
1. `SyncManager` sees online → drains FIFO.
2. `createLog` upsert (explicit id) → row exists.
3. `createAttachment`: upload local file → `logs/{logId}/{attachmentId}.png`
   (upsert) → get public URL → upsert attachment row → patch cache → optionally
   delete the local pending file.
4. Remove ops; `pendingCount → 0`; toast "Back online — synced N".
   FIFO guarantees the log row exists before its image uploads (Storage RLS
   requires the referenced log to exist and be owned by the caller).

### 5.3 Delete a not-yet-synced log
- If the log still has a queued `createLog` op → `cancelCreateFor(logId)`
  removes the pending `createLog` + its `createAttachment` ops and the cache
  entry. **No `deleteLog` is enqueued** (the row never reached the server).
- If the log was already synced to Supabase → enqueue `deleteLog`.

### 5.4 GitHub sync (Layer B) stays manual & online-only
- "Sync GitHub", "Add Repository", mark-finished, close-issue require network.
  Disabled offline with a hint. Unchanged logic.

---

## 6. UI Changes

- **Global offline banner** (in a wrapper around the authed shell): "You're
  offline — changes will sync when you reconnect." Reconnect shows a transient
  "Back online — syncing N…" → "synced".
- **"Keep Local" works offline** (goes through cache+queue) — fixes the throw.
- **"Sync GitHub"** and **"Add Repository"** disabled offline with a tooltip/note.
- **"Pending sync" badge** on `LogCard`s whose id has a queued op
  (driven by `SyncQueue`, independent of `sync_status`).
- **Attachment previews** render a **local file** (pending) or **network URL**
  (synced) — `LogDetailPage`/preview must branch on `File.existsSync()` vs URL.

---

## 7. Error Handling & Edge Cases

- **Read timeout (8s)** → cache fallback, so captive portals / weak signal
  never hang (kills the stall even when `isOnline` is a false positive).
- **Drain op rejected by server** (e.g., validation) → op kept, `markError`,
  retry offered; data never lost.
- **Storage RLS ordering** → FIFO ensures log-insert precedes image-upload.
- **App killed mid-drain** → on next launch, remaining ops replay; idempotency
  (§3) makes this safe.
- **User signs out** → clear that user's cache + queue (they hold personal data;
  aligns with existing secure-token clearing on sign-out).
- **Account deletion** → also clears local cache + queue + pending files.

---

## 8. Dependencies

Added (all small; negligible APK impact — no native DB):
- `connectivity_plus`
- `uuid`
- `path_provider`

No Supabase schema/RLS change required (upsert uses existing insert+update
grants and policies; storage path change is client-side).

---

## 9. Testing

- **`SyncQueue`**: FIFO ordering; `remove`; `markError`; `cancelCreateFor`
  removes create+attachment ops and enqueues no delete.
- **`LocalCache`**: JSON round-trips for repos/logs/attachments per user.
- **`SupabaseService` offline**: with a fake `ConnectivityService` + fake
  Supabase client — reads fall back to cache; writes enqueue + optimistic cache;
  online writes drain.
- **`SyncManager` idempotency (the ghost-log regression test)**: draining the
  same `createLog` op twice results in **one** row (upsert on client id);
  uploading the same attachment twice yields one storage object + one row.
- **Widget**: offline banner appears; "Keep Local" succeeds offline; "Sync
  GitHub"/"Add Repository" disabled offline; "Pending sync" badge shows.

---

## 10. File-Level Change Summary

- **New:** `lib/app/services/offline/connectivity_service.dart`,
  `local_cache.dart`, `sync_queue.dart`, `sync_manager.dart`.
- **Modified:** `supabase_service.dart` (offline-aware reads/writes, upsert,
  deterministic storage path, client UUIDs), `log_controller.dart` (unchanged
  surface, but writes now non-throwing offline),
  `create_log_page.dart` (attachment preview already local-file aware;
  offline-aware button states), `home_controller.dart`/pages (cache-backed loads
  don't stall), `boot.dart` (wire `SyncManager` start), a small offline banner
  widget, `LogCard` (pending badge), `pubspec.yaml` (3 deps).
- **Docs:** update `DEVELOPER.md` (offline-first section) after implementation.
```
