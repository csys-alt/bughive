# BugHive Offline-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in user use BugHive fully offline (browse cache, create/edit/delete logs, attach images), auto-syncing to Supabase on reconnect with idempotent (no-duplicate) writes; GitHub issue sync stays manual/online.

**Architecture:** Introduce a testable seam — `RemoteDataSource` (thin Supabase wrapper) — plus four small offline units (`ConnectivityService`, `KeyValueStore`, `LocalCache`, `SyncQueue`) and a `SyncManager` that drains a FIFO operation queue idempotently. `SupabaseService` keeps its public API but internally becomes offline-aware (network-first reads with cache fallback; writes = optimistic cache + enqueue + best-effort drain). All writes use **client-generated UUIDs + `upsert`**, so replay never duplicates.

**Tech Stack:** Flutter/Dart, Nylo, Supabase, `connectivity_plus`, `uuid`, `path_provider`, NyStorage.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-14-offline-first-design.md`. Philosophy: **write first, sync when you're ready**.
- **Idempotency is mandatory:** client UUID PKs, `upsert(onConflict: "id")`, deterministic storage path `logs/{logId}/{attachmentId}.png` with `upsert: true`, remove a queue op only after its remote write is confirmed.
- **`sync_status` (LOCAL/SYNCED/CLOSED) is GitHub state only.** "Pending device→cloud" is queue membership, never a `sync_status` mutation.
- Layer A (device→Supabase) auto on reconnect; Layer B (Supabase→GitHub, "Sync GitHub"/"Add Repository"/close) stays manual and online-only.
- No Supabase schema/RLS change (upsert uses existing insert+update grants).
- Dart SDK `^3.10.7`. Dark mode only. Follow existing file/style conventions.
- New offline units live in `lib/app/services/offline/`.
- Tests are pure-Dart where possible (no Flutter binding) by depending on the `KeyValueStore` abstraction and fakes.
- Commit after every task. Branch first (repo is on `main`).

---

## File Structure

- `lib/app/services/offline/connectivity_service.dart` — `ConnectivityService` (abstract) + `ConnectivityPlusService`.
- `lib/app/services/offline/key_value_store.dart` — `KeyValueStore` (abstract), `NyKeyValueStore`, `InMemoryKeyValueStore`.
- `lib/app/services/offline/sync_operation.dart` — `SyncOperation` + `SyncOpType`.
- `lib/app/services/offline/sync_queue.dart` — `SyncQueue`.
- `lib/app/services/offline/local_cache.dart` — `LocalCache`.
- `lib/app/services/offline/remote_data_source.dart` — `RemoteDataSource` (abstract) + `SupabaseRemote`.
- `lib/app/services/offline/sync_manager.dart` — `SyncManager`.
- `lib/app/services/offline/offline_runtime.dart` — composition root singleton.
- `lib/app/services/supabase_service.dart` — modified to be offline-aware.
- `lib/resources/widgets/offline_banner.dart` — banner widget.
- `lib/resources/widgets/log_card.dart`, `lib/resources/pages/create_log_page.dart`, `lib/resources/pages/log_detail_page.dart` — UI states.
- `lib/bootstrap/boot.dart` — wire runtime + start SyncManager.
- `test/offline/*` — unit/widget tests.

---

## Task 1: Dependencies + ConnectivityService

**Files:**
- Modify: `pubspec.yaml:11-21` (dependencies block)
- Create: `lib/app/services/offline/connectivity_service.dart`
- Test: `test/offline/connectivity_service_test.dart`

**Interfaces:**
- Produces:
  - `abstract class ConnectivityService { bool get isOnline; Stream<bool> get onStatusChange; Future<void> start(); void dispose(); }`
  - `class ConnectivityPlusService implements ConnectivityService`
  - `class FakeConnectivityService implements ConnectivityService` (in test file) with `void emit(bool online)`.

- [ ] **Step 1: Add dependencies**

Edit `pubspec.yaml` dependencies (keep alphabetical-ish with existing):

```yaml
  connectivity_plus: ^6.1.0
  uuid: ^4.5.1
  path_provider: ^2.1.5
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: resolves without version conflicts.

- [ ] **Step 3: Write the failing test**

```dart
// test/offline/connectivity_service_test.dart
import 'dart:async';
import 'package:bughive/app/services/offline/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConnectivityService implements ConnectivityService {
  bool _online = true;
  final _controller = StreamController<bool>.broadcast();
  @override
  bool get isOnline => _online;
  @override
  Stream<bool> get onStatusChange => _controller.stream;
  @override
  Future<void> start() async {}
  @override
  void dispose() => _controller.close();
  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }
}

void main() {
  test('fake emits status transitions and updates isOnline', () async {
    final fake = FakeConnectivityService();
    expect(fake.isOnline, isTrue);
    final events = <bool>[];
    final sub = fake.onStatusChange.listen(events.add);
    fake.emit(false);
    fake.emit(true);
    await Future.delayed(Duration.zero);
    expect(fake.isOnline, isTrue);
    expect(events, [false, true]);
    await sub.cancel();
    fake.dispose();
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/offline/connectivity_service_test.dart`
Expected: FAIL — `connectivity_service.dart` / `ConnectivityService` not found.

- [ ] **Step 5: Implement ConnectivityService**

```dart
// lib/app/services/offline/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports device connectivity. `isOnline` is a cached snapshot updated from
/// the platform stream; treat it as best-effort — a write that fails on a
/// false-positive simply stays queued.
abstract class ConnectivityService {
  bool get isOnline;
  Stream<bool> get onStatusChange;
  Future<void> start();
  void dispose();
}

class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<void> start() async {
    _isOnline = _resultsOnline(await _connectivity.checkConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final next = _resultsOnline(results);
      if (next == _isOnline) return;
      _isOnline = next;
      _controller.add(next);
    });
  }

  bool _resultsOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/offline/connectivity_service_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/app/services/offline/connectivity_service.dart test/offline/connectivity_service_test.dart
git commit -m "feat(offline): add connectivity service + deps"
```

---

## Task 2: KeyValueStore + SyncOperation + SyncQueue

**Files:**
- Create: `lib/app/services/offline/key_value_store.dart`
- Create: `lib/app/services/offline/sync_operation.dart`
- Create: `lib/app/services/offline/sync_queue.dart`
- Test: `test/offline/sync_queue_test.dart`

**Interfaces:**
- Produces:
  - `abstract class KeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`
  - `class InMemoryKeyValueStore implements KeyValueStore`
  - `enum SyncOpType { createLog, updateLog, deleteLog, createAttachment }`
  - `class SyncOperation { final String opId; final SyncOpType type; final Map<String,dynamic> payload; final String? localFilePath; final DateTime createdAt; final String? error; ... toJson()/fromJson() }`
  - `class SyncQueue { SyncQueue(this._store, this._userId); Future<void> enqueue(SyncOperation op); Future<List<SyncOperation>> all(); Future<void> remove(String opId); Future<void> markError(String opId, String message); Future<void> cancelCreateFor(String logId); Future<int> count(); Future<bool> hasPendingCreate(String logId); Future<void> clear(); final ValueNotifier<int> pending; }`
  - Payload convention: create/update/deleteLog payload includes `"id"` (log id); createLog/updateLog payload is the full `log.toSupabaseJson()`; deleteLog payload is `{"id": logId}`; createAttachment payload is `attachment.toSupabaseJson()` (always includes `"id"` and `"log_id"`).

- [ ] **Step 1: Write the failing test**

```dart
// test/offline/sync_queue_test.dart
import 'package:bughive/app/services/offline/key_value_store.dart';
import 'package:bughive/app/services/offline/sync_operation.dart';
import 'package:bughive/app/services/offline/sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';

SyncOperation _op(String opId, SyncOpType type, String logId) => SyncOperation(
      opId: opId,
      type: type,
      payload: type == SyncOpType.createAttachment
          ? {"id": opId, "log_id": logId}
          : {"id": logId},
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late InMemoryKeyValueStore store;
  late SyncQueue queue;

  setUp(() {
    store = InMemoryKeyValueStore();
    queue = SyncQueue(store, "user-1");
  });

  test('enqueue preserves FIFO order and survives reload', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.enqueue(_op("b", SyncOpType.updateLog, "log-1"));
    final reloaded = SyncQueue(store, "user-1");
    final all = await reloaded.all();
    expect(all.map((o) => o.opId), ["a", "b"]);
  });

  test('remove deletes by opId', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.enqueue(_op("b", SyncOpType.updateLog, "log-1"));
    await queue.remove("a");
    final all = await queue.all();
    expect(all.map((o) => o.opId), ["b"]);
  });

  test('markError records message without removing op', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.markError("a", "boom");
    final all = await queue.all();
    expect(all.single.error, "boom");
  });

  test('cancelCreateFor removes createLog + its attachments, no delete left',
      () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.enqueue(_op("img", SyncOpType.createAttachment, "log-1"));
    await queue.enqueue(_op("b", SyncOpType.createLog, "log-2"));
    await queue.cancelCreateFor("log-1");
    final all = await queue.all();
    expect(all.map((o) => o.opId), ["b"]);
  });

  test('hasPendingCreate reflects queue', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    expect(await queue.hasPendingCreate("log-1"), isTrue);
    expect(await queue.hasPendingCreate("log-2"), isFalse);
  });

  test('pending notifier tracks count', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    expect(queue.pending.value, 1);
    await queue.remove("a");
    expect(queue.pending.value, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline/sync_queue_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement KeyValueStore**

```dart
// lib/app/services/offline/key_value_store.dart
import 'package:nylo_framework/nylo_framework.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class NyKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) => NyStorage.read<String>(key);

  @override
  Future<void> write(String key, String value) => NyStorage.save(key, value);

  @override
  Future<void> delete(String key) => NyStorage.delete(key);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
```

> Verified against `nylo_support 7.27.2`: `NyStorage.save(String key, dynamic
> value)`, `NyStorage.read<T>(String key)` (use `read<String>`), and
> `NyStorage.delete(String key)`. `save` wraps the value in a typed envelope and
> `read<String>` unwraps it, so the JSON string round-trips cleanly.

- [ ] **Step 4: Implement SyncOperation**

```dart
// lib/app/services/offline/sync_operation.dart
enum SyncOpType { createLog, updateLog, deleteLog, createAttachment }

class SyncOperation {
  final String opId;
  final SyncOpType type;
  final Map<String, dynamic> payload;
  final String? localFilePath;
  final DateTime createdAt;
  final String? error;

  const SyncOperation({
    required this.opId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.localFilePath,
    this.error,
  });

  String get logId {
    if (type == SyncOpType.createAttachment) {
      return payload["log_id"]?.toString() ?? "";
    }
    return payload["id"]?.toString() ?? "";
  }

  SyncOperation copyWith({String? error}) => SyncOperation(
        opId: opId,
        type: type,
        payload: payload,
        createdAt: createdAt,
        localFilePath: localFilePath,
        error: error ?? this.error,
      );

  Map<String, dynamic> toJson() => {
        "opId": opId,
        "type": type.name,
        "payload": payload,
        "localFilePath": localFilePath,
        "createdAt": createdAt.toUtc().toIso8601String(),
        "error": error,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        opId: json["opId"] as String,
        type: SyncOpType.values.firstWhere((t) => t.name == json["type"]),
        payload: Map<String, dynamic>.from(json["payload"] as Map),
        localFilePath: json["localFilePath"] as String?,
        createdAt:
            DateTime.tryParse(json["createdAt"]?.toString() ?? "")?.toUtc() ??
                DateTime.now().toUtc(),
        error: json["error"] as String?,
      );
}
```

- [ ] **Step 5: Implement SyncQueue**

```dart
// lib/app/services/offline/sync_queue.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'key_value_store.dart';
import 'sync_operation.dart';

class SyncQueue {
  SyncQueue(this._store, this._userId) {
    _prime();
  }

  final KeyValueStore _store;
  final String _userId;
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  String get _key => "sync_queue:$_userId";

  Future<void> _prime() async {
    pending.value = (await all()).length;
  }

  Future<List<SyncOperation>> all() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SyncOperation.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _save(List<SyncOperation> ops) async {
    await _store.write(_key, jsonEncode(ops.map((o) => o.toJson()).toList()));
    pending.value = ops.length;
  }

  Future<void> enqueue(SyncOperation op) async {
    final ops = await all()..add(op);
    await _save(ops);
  }

  Future<void> remove(String opId) async {
    final ops = await all()..removeWhere((o) => o.opId == opId);
    await _save(ops);
  }

  Future<void> markError(String opId, String message) async {
    final ops = await all();
    final next = ops
        .map((o) => o.opId == opId ? o.copyWith(error: message) : o)
        .toList();
    await _save(next);
  }

  Future<void> cancelCreateFor(String logId) async {
    final ops = await all()
      ..removeWhere((o) =>
          (o.type == SyncOpType.createLog ||
              o.type == SyncOpType.createAttachment) &&
          o.logId == logId);
    await _save(ops);
  }

  Future<bool> hasPendingCreate(String logId) async {
    final ops = await all();
    return ops.any(
        (o) => o.type == SyncOpType.createLog && o.logId == logId);
  }

  Future<Set<String>> pendingLogIds() async {
    final ops = await all();
    return ops.map((o) => o.logId).where((id) => id.isNotEmpty).toSet();
  }

  Future<int> count() async => (await all()).length;

  Future<void> clear() async {
    await _store.delete(_key);
    pending.value = 0;
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/offline/sync_queue_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/app/services/offline/key_value_store.dart lib/app/services/offline/sync_operation.dart lib/app/services/offline/sync_queue.dart test/offline/sync_queue_test.dart
git commit -m "feat(offline): key-value store, sync operation, and sync queue"
```

---

## Task 3: LocalCache

**Files:**
- Create: `lib/app/services/offline/local_cache.dart`
- Test: `test/offline/local_cache_test.dart`

**Interfaces:**
- Consumes: `KeyValueStore` (Task 2), models `Repository`/`EngineeringLog`/`Attachment`.
- Produces: `class LocalCache { LocalCache(this._store, this._userId); Future<List<Repository>> readRepos(); Future<void> writeRepos(List<Repository>); Future<List<EngineeringLog>> readLogs(String repoId); Future<void> writeLogs(String repoId, List<EngineeringLog>); Future<void> upsertLog(EngineeringLog); Future<void> removeLog(EngineeringLog); Future<List<Attachment>> readAttachments(String logId); Future<void> writeAttachments(String logId, List<Attachment>); Future<void> upsertAttachment(Attachment); Future<void> clear(); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/offline/local_cache_test.dart
import 'package:bughive/app/models/engineering_log.dart';
import 'package:bughive/app/models/repository.dart';
import 'package:bughive/app/services/offline/key_value_store.dart';
import 'package:bughive/app/services/offline/local_cache.dart';
import 'package:flutter_test/flutter_test.dart';

EngineeringLog _log(String id, String repoId, String title) => EngineeringLog(
      id: id,
      repoId: repoId,
      userId: "u1",
      title: title,
      description: "d",
      type: EngineeringLogType.bug,
      severity: Severity.medium,
      environment: "env",
      labels: const [],
    );

void main() {
  late LocalCache cache;
  setUp(() => cache = LocalCache(InMemoryKeyValueStore(), "u1"));

  test('repos round-trip', () async {
    await cache.writeRepos([
      const Repository(id: "r1", githubRepoId: 1, owner: "o", name: "n", url: "u"),
    ]);
    final repos = await cache.readRepos();
    expect(repos.single.id, "r1");
    expect(repos.single.fullName, "o/n");
  });

  test('upsertLog inserts then replaces by id', () async {
    await cache.upsertLog(_log("l1", "r1", "first"));
    await cache.upsertLog(_log("l1", "r1", "second"));
    final logs = await cache.readLogs("r1");
    expect(logs.length, 1);
    expect(logs.single.title, "second");
  });

  test('removeLog drops the entry', () async {
    await cache.upsertLog(_log("l1", "r1", "x"));
    await cache.removeLog(_log("l1", "r1", "x"));
    expect(await cache.readLogs("r1"), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline/local_cache_test.dart`
Expected: FAIL — `local_cache.dart` not found.

- [ ] **Step 3: Implement LocalCache**

```dart
// lib/app/services/offline/local_cache.dart
import 'dart:convert';
import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import 'key_value_store.dart';

class LocalCache {
  LocalCache(this._store, this._userId);

  final KeyValueStore _store;
  final String _userId;

  String _reposKey() => "cache:repos:$_userId";
  String _logsKey(String repoId) => "cache:logs:$_userId:$repoId";
  String _attachmentsKey(String logId) => "cache:att:$_userId:$logId";

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final raw = await _store.read(key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> rows) =>
      _store.write(key, jsonEncode(rows));

  Future<List<Repository>> readRepos() async =>
      (await _readList(_reposKey())).map(Repository.fromJson).toList();

  Future<void> writeRepos(List<Repository> repos) =>
      _writeList(_reposKey(), repos.map((r) => r.toSupabaseJson()).toList());

  Future<List<EngineeringLog>> readLogs(String repoId) async =>
      (await _readList(_logsKey(repoId))).map(EngineeringLog.fromJson).toList();

  Future<void> writeLogs(String repoId, List<EngineeringLog> logs) => _writeList(
      _logsKey(repoId), logs.map((l) => l.toSupabaseJson()).toList());

  Future<void> upsertLog(EngineeringLog log) async {
    final logs = await readLogs(log.repoId);
    final next = [
      log,
      ...logs.where((l) => l.id != log.id),
    ];
    await writeLogs(log.repoId, next);
  }

  Future<void> removeLog(EngineeringLog log) async {
    final logs = await readLogs(log.repoId);
    await writeLogs(log.repoId, logs.where((l) => l.id != log.id).toList());
  }

  Future<List<Attachment>> readAttachments(String logId) async =>
      (await _readList(_attachmentsKey(logId)))
          .map(Attachment.fromJson)
          .toList();

  Future<void> writeAttachments(String logId, List<Attachment> items) =>
      _writeList(_attachmentsKey(logId),
          items.map((a) => a.toSupabaseJson()).toList());

  Future<void> upsertAttachment(Attachment attachment) async {
    final items = await readAttachments(attachment.logId);
    final next = [
      attachment,
      ...items.where((a) => a.id != attachment.id),
    ];
    await writeAttachments(attachment.logId, next);
  }

  Future<void> clear() async {
    await _store.delete(_reposKey());
    // Log/attachment buckets are keyed per repo/log; callers that need a full
    // wipe should re-fetch after clear(). For sign-out we also clear the queue
    // and rely on fresh login re-populating caches.
  }
}
```

> `Attachment.toSupabaseJson()` omits `created_at`; that's fine for cache — the
> UI never depends on a cached attachment's timestamp.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/offline/local_cache_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/services/offline/local_cache.dart test/offline/local_cache_test.dart
git commit -m "feat(offline): local cache for repos/logs/attachments"
```

---

## Task 4: RemoteDataSource + SupabaseRemote (extract network layer)

**Files:**
- Create: `lib/app/services/offline/remote_data_source.dart`
- Modify: `lib/app/services/supabase_service.dart` (move data-method bodies into `SupabaseRemote`; `SupabaseService` delegates for now)
- Test: manual build + existing tests (no new unit test — this is a behavior-preserving extraction, except insert→upsert and deterministic storage path)

**Interfaces:**
- Produces `abstract class RemoteDataSource` with:
  - `Future<List<Repository>> fetchRepositories()`
  - `Future<List<EngineeringLog>> fetchEngineeringLogs(String repoId, {SyncStatus? status})`
  - `Future<List<Attachment>> fetchAttachments(String logId)`
  - `Future<LogCounts> fetchLogCounts(String repoId)`
  - `Future<Repository> saveRepository(Repository repository)`
  - `Future<Repository> markRepositorySynced(Repository repository)`
  - `Future<void> deleteRepository(Repository repository)`
  - `Future<EngineeringLog> upsertLog(EngineeringLog log)`
  - `Future<EngineeringLog> markLogSynced({required EngineeringLog log, required int githubIssueNumber})`
  - `Future<EngineeringLog> markLogFinished(EngineeringLog log)`
  - `Future<void> deleteLog(String logId)`
  - `Future<Attachment> upsertAttachment(Attachment attachment)`
  - `Future<Attachment> uploadScreenshot({required String logId, required String attachmentId, required File file})`
- `class SupabaseRemote implements RemoteDataSource` using `Supabase.instance.client`.

- [ ] **Step 1: Create RemoteDataSource + SupabaseRemote**

Move the current bodies of `fetchRepositories`, `fetchLogCounts`, `saveRepository`, `markRepositorySynced`, `deleteRepository`, `fetchEngineeringLogs`, `markLogSynced`, `markLogFinished`, `fetchAttachments`, plus **upsert** variants, into `SupabaseRemote`. Key changes vs current code:

```dart
// lib/app/services/offline/remote_data_source.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/services/supabase_service.dart' show LogCounts, SupabaseServiceException;

abstract class RemoteDataSource {
  Future<List<Repository>> fetchRepositories();
  Future<List<EngineeringLog>> fetchEngineeringLogs(String repoId, {SyncStatus? status});
  Future<List<Attachment>> fetchAttachments(String logId);
  Future<LogCounts> fetchLogCounts(String repoId);
  Future<Repository> saveRepository(Repository repository);
  Future<Repository> markRepositorySynced(Repository repository);
  Future<void> deleteRepository(Repository repository);
  Future<EngineeringLog> upsertLog(EngineeringLog log);
  Future<EngineeringLog> markLogSynced({required EngineeringLog log, required int githubIssueNumber});
  Future<EngineeringLog> markLogFinished(EngineeringLog log);
  Future<void> deleteLog(String logId);
  Future<Attachment> upsertAttachment(Attachment attachment);
  Future<Attachment> uploadScreenshot({required String logId, required String attachmentId, required File file});
}

class SupabaseRemote implements RemoteDataSource {
  supabase.SupabaseClient get _client => supabase.Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic response) => (response as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  Future<EngineeringLog> upsertLog(EngineeringLog log) async {
    final response = await _client
        .from("engineering_logs")
        .upsert(log.toSupabaseJson(), onConflict: "id")
        .select()
        .single();
    return EngineeringLog.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> deleteLog(String logId) async {
    await _client.from("engineering_logs").delete().eq("id", logId);
  }

  @override
  Future<Attachment> upsertAttachment(Attachment attachment) async {
    final response = await _client
        .from("attachments")
        .upsert(attachment.toSupabaseJson(), onConflict: "id")
        .select()
        .single();
    return Attachment.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<Attachment> uploadScreenshot({
    required String logId,
    required String attachmentId,
    required File file,
  }) async {
    final path = "logs/$logId/$attachmentId.png";
    await _client.storage.from("bughive").upload(
          path,
          file,
          fileOptions: const supabase.FileOptions(upsert: true),
        );
    final publicUrl = _client.storage.from("bughive").getPublicUrl(path);
    return upsertAttachment(
      Attachment(id: attachmentId, logId: logId, fileUrl: publicUrl),
    );
  }

  // fetchRepositories / fetchEngineeringLogs / fetchAttachments /
  // fetchLogCounts / saveRepository / markRepositorySynced /
  // deleteRepository / markLogSynced / markLogFinished:
  // COPY the exact bodies currently in supabase_service.dart (they already use
  // `_client` and `_rows`), unchanged.
}
```

> Copy the remaining method bodies verbatim from
> `lib/app/services/supabase_service.dart` (lines ~259–441 in the current file).
> `saveRepository` keeps using `.upsert(..., onConflict: "user_id,github_repo_id")`
> if it already does; otherwise leave it as the existing insert — repositories
> are online-only so idempotency there is out of scope.

- [ ] **Step 2: Make SupabaseService delegate (temporary)**

In `supabase_service.dart`, add a `RemoteDataSource _remote = SupabaseRemote();` field and replace each data-method body with a delegation, e.g.:

```dart
Future<List<Repository>> fetchRepositories() => _remote.fetchRepositories();
Future<EngineeringLog> createEngineeringLog(EngineeringLog log) =>
    _remote.upsertLog(log);
Future<EngineeringLog> updateEngineeringLog(EngineeringLog log) {
  if (log.id == null) {
    throw const SupabaseServiceException("Log must be saved first.");
  }
  return _remote.upsertLog(log);
}
Future<void> deleteEngineeringLog(EngineeringLog log) async {
  if (log.id == null) return;
  await _remote.deleteLog(log.id!);
}
Future<Attachment> createAttachment(Attachment attachment) =>
    _remote.upsertAttachment(attachment);
Future<Attachment> uploadScreenshot({required String logId, required File file}) {
  // temporary: keep old signature; generate id here until Task 6 moves it.
  final id = DateTime.now().microsecondsSinceEpoch.toString();
  return _remote.uploadScreenshot(logId: logId, attachmentId: id, file: file);
}
```

Keep `LogCounts`/`SupabaseServiceException` classes where they are (still exported from `supabase_service.dart`).

- [ ] **Step 3: Verify the app builds**

Run: `flutter analyze`
Expected: no errors (warnings from pre-existing code acceptable).

- [ ] **Step 4: Verify existing offline unit tests still pass**

Run: `flutter test test/offline/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/services/offline/remote_data_source.dart lib/app/services/supabase_service.dart
git commit -m "refactor(offline): extract RemoteDataSource; use upsert + deterministic storage path"
```

---

## Task 5: SyncManager (idempotent FIFO drain) — the ghost-log fix

**Files:**
- Create: `lib/app/services/offline/sync_manager.dart`
- Test: `test/offline/sync_manager_test.dart`

**Interfaces:**
- Consumes: `RemoteDataSource`, `SyncQueue`, `LocalCache`, `ConnectivityService`.
- Produces: `class SyncManager { SyncManager({required RemoteDataSource remote, required SyncQueue queue, required LocalCache cache, required ConnectivityService connectivity}); Future<void> drain(); void start(); ValueNotifier<int> get pending; void dispose(); }`

- [ ] **Step 1: Write the failing test (idempotency is the key case)**

```dart
// test/offline/sync_manager_test.dart
import 'dart:io';
import 'package:bughive/app/models/attachment.dart';
import 'package:bughive/app/models/engineering_log.dart';
import 'package:bughive/app/models/repository.dart';
import 'package:bughive/app/services/offline/key_value_store.dart';
import 'package:bughive/app/services/offline/local_cache.dart';
import 'package:bughive/app/services/offline/remote_data_source.dart';
import 'package:bughive/app/services/offline/sync_manager.dart';
import 'package:bughive/app/services/offline/sync_operation.dart';
import 'package:bughive/app/services/offline/sync_queue.dart';
import 'package:bughive/app/services/supabase_service.dart' show LogCounts;
import 'package:flutter_test/flutter_test.dart';
import '../offline/connectivity_service_test.dart' show FakeConnectivityService;

/// Fake remote keyed by id — upsert is idempotent by construction.
class FakeRemote implements RemoteDataSource {
  final Map<String, EngineeringLog> logs = {};
  final Map<String, Attachment> attachments = {};
  int uploadCalls = 0;

  @override
  Future<EngineeringLog> upsertLog(EngineeringLog log) async {
    logs[log.id!] = log;
    return log;
  }

  @override
  Future<void> deleteLog(String logId) async => logs.remove(logId);

  @override
  Future<Attachment> upsertAttachment(Attachment a) async {
    attachments[a.id!] = a;
    return a;
  }

  @override
  Future<Attachment> uploadScreenshot({
    required String logId,
    required String attachmentId,
    required File file,
  }) async {
    uploadCalls++;
    final a = Attachment(
        id: attachmentId, logId: logId, fileUrl: "https://cdn/$attachmentId.png");
    attachments[attachmentId] = a;
    return a;
  }

  @override
  Future<List<Repository>> fetchRepositories() async => [];
  @override
  Future<List<EngineeringLog>> fetchEngineeringLogs(String repoId, {SyncStatus? status}) async => [];
  @override
  Future<List<Attachment>> fetchAttachments(String logId) async => [];
  @override
  Future<LogCounts> fetchLogCounts(String repoId) async =>
      const LogCounts(total: 0, local: 0, synced: 0);
  @override
  Future<Repository> saveRepository(Repository repository) async => repository;
  @override
  Future<Repository> markRepositorySynced(Repository repository) async => repository;
  @override
  Future<void> deleteRepository(Repository repository) async {}
  @override
  Future<EngineeringLog> markLogSynced({required EngineeringLog log, required int githubIssueNumber}) async => log;
  @override
  Future<EngineeringLog> markLogFinished(EngineeringLog log) async => log;
}

SyncOperation _createLogOp(String id) => SyncOperation(
      opId: "op-$id",
      type: SyncOpType.createLog,
      payload: {
        "id": id,
        "repo_id": "r1",
        "user_id": "u1",
        "title": "t",
        "description": "d",
        "type": "BUG",
        "severity": "MEDIUM",
        "environment": "e",
        "labels": <String>[],
        "sync_status": "LOCAL",
      },
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late FakeRemote remote;
  late SyncQueue queue;
  late LocalCache cache;
  late FakeConnectivityService conn;
  late SyncManager manager;

  setUp(() {
    final store = InMemoryKeyValueStore();
    remote = FakeRemote();
    queue = SyncQueue(store, "u1");
    cache = LocalCache(store, "u1");
    conn = FakeConnectivityService();
    manager = SyncManager(remote: remote, queue: queue, cache: cache, connectivity: conn);
  });

  test('draining the same createLog op twice yields ONE row (no ghost)', () async {
    await queue.enqueue(_createLogOp("log-1"));
    await manager.drain();
    // Simulate a replay: re-enqueue an identical op (same id) and drain again.
    await queue.enqueue(_createLogOp("log-1"));
    await manager.drain();
    expect(remote.logs.length, 1);
    expect(await queue.count(), 0);
  });

  test('createAttachment uploads then patches cache with CDN url', () async {
    await queue.enqueue(_createLogOp("log-1"));
    await queue.enqueue(SyncOperation(
      opId: "op-img",
      type: SyncOpType.createAttachment,
      payload: {"id": "att-1", "log_id": "log-1", "file_url": "/tmp/x.png"},
      localFilePath: "/tmp/x.png",
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    await manager.drain();
    expect(remote.uploadCalls, 1);
    final cached = await cache.readAttachments("log-1");
    expect(cached.single.fileUrl, startsWith("https://cdn/"));
    expect(await queue.count(), 0);
  });

  test('a failing op is kept and marked, draining stops after it', () async {
    // Point remote.upsertLog to throw for a specific id by using a bad payload.
    await queue.enqueue(SyncOperation(
      opId: "bad",
      type: SyncOpType.createLog,
      payload: const {"id": null}, // upsert(log.id!) throws
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    await manager.drain();
    final ops = await queue.all();
    expect(ops.single.error, isNotNull);
  });
}
```

> Note: the file uploaded in the second test doesn't need to exist on disk —
> `FakeRemote.uploadScreenshot` ignores the file. If a future real-file test is
> added, create a temp file first.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline/sync_manager_test.dart`
Expected: FAIL — `sync_manager.dart` not found.

- [ ] **Step 3: Implement SyncManager**

```dart
// lib/app/services/offline/sync_manager.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import 'connectivity_service.dart';
import 'local_cache.dart';
import 'remote_data_source.dart';
import 'sync_operation.dart';
import 'sync_queue.dart';

class SyncManager {
  SyncManager({
    required RemoteDataSource remote,
    required SyncQueue queue,
    required LocalCache cache,
    required ConnectivityService connectivity,
  })  : _remote = remote,
        _queue = queue,
        _cache = cache,
        _connectivity = connectivity;

  final RemoteDataSource _remote;
  final SyncQueue _queue;
  final LocalCache _cache;
  final ConnectivityService _connectivity;

  StreamSubscription<bool>? _sub;
  bool _draining = false;

  ValueNotifier<int> get pending => _queue.pending;

  void start() {
    _sub = _connectivity.onStatusChange.listen((online) {
      if (online) drain();
    });
    if (_connectivity.isOnline) drain();
  }

  /// Drains the queue in FIFO order. Each op is removed only after its remote
  /// write is confirmed; a failing op is marked and stops the drain so ordering
  /// (log-before-attachment) is preserved.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final op in await _queue.all()) {
        try {
          await _apply(op);
          await _queue.remove(op.opId);
        } catch (error) {
          await _queue.markError(op.opId, error.toString());
          break;
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _apply(SyncOperation op) async {
    switch (op.type) {
      case SyncOpType.createLog:
      case SyncOpType.updateLog:
        final saved = await _remote.upsertLog(EngineeringLog.fromJson(op.payload));
        await _cache.upsertLog(saved);
        break;
      case SyncOpType.deleteLog:
        await _remote.deleteLog(op.payload["id"].toString());
        break;
      case SyncOpType.createAttachment:
        final Attachment saved;
        if (op.localFilePath != null && op.localFilePath!.isNotEmpty) {
          saved = await _remote.uploadScreenshot(
            logId: op.payload["log_id"].toString(),
            attachmentId: op.payload["id"].toString(),
            file: File(op.localFilePath!),
          );
        } else {
          saved = await _remote.upsertAttachment(Attachment.fromJson(op.payload));
        }
        await _cache.upsertAttachment(saved);
        break;
    }
  }

  void dispose() => _sub?.cancel();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/offline/sync_manager_test.dart`
Expected: PASS (3 tests) — including the ghost-log regression.

- [ ] **Step 5: Commit**

```bash
git add lib/app/services/offline/sync_manager.dart test/offline/sync_manager_test.dart
git commit -m "feat(offline): idempotent FIFO SyncManager (fixes ghost duplicate logs)"
```

---

## Task 6: Make SupabaseService offline-aware + OfflineRuntime

**Files:**
- Create: `lib/app/services/offline/offline_runtime.dart`
- Modify: `lib/app/services/supabase_service.dart`
- Test: `test/offline/supabase_service_offline_test.dart`

**Interfaces:**
- Produces:
  - `class OfflineRuntime { static OfflineRuntime? _i; static OfflineRuntime get instance; RemoteDataSource remote; ConnectivityService connectivity; LocalCache cacheFor(String userId); SyncQueue queueFor(String userId); SyncManager managerFor(String userId); }`
  - `SupabaseService` gains optional constructor injection: `SupabaseService({RemoteDataSource? remote, ConnectivityService? connectivity, LocalCache? cache, SyncQueue? queue, SyncManager? syncManager})` defaulting to `OfflineRuntime.instance` (namespaced by `currentUserId`).
- Consumes: everything from Tasks 1–5.

- [ ] **Step 1: Write the failing test**

```dart
// test/offline/supabase_service_offline_test.dart
import 'package:bughive/app/models/engineering_log.dart';
import 'package:bughive/app/models/repository.dart';
import 'package:bughive/app/services/offline/key_value_store.dart';
import 'package:bughive/app/services/offline/local_cache.dart';
import 'package:bughive/app/services/offline/sync_manager.dart';
import 'package:bughive/app/services/offline/sync_queue.dart';
import 'package:bughive/app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connectivity_service_test.dart' show FakeConnectivityService;
import 'sync_manager_test.dart' show FakeRemote;

void main() {
  test('createEngineeringLog offline: enqueues + caches, assigns id, no throw',
      () async {
    final store = InMemoryKeyValueStore();
    final remote = FakeRemote();
    final conn = FakeConnectivityService()..emit(false);
    final queue = SyncQueue(store, "u1");
    final cache = LocalCache(store, "u1");
    final manager = SyncManager(remote: remote, queue: queue, cache: cache, connectivity: conn);
    final service = SupabaseService(
      remote: remote, connectivity: conn, cache: cache, queue: queue, syncManager: manager,
    );

    final saved = await service.createEngineeringLog(EngineeringLog(
      repoId: "r1", userId: "u1", title: "t", description: "d",
      type: EngineeringLogType.bug, severity: Severity.medium,
      environment: "e", labels: const [],
    ));

    expect(saved.id, isNotNull);                 // client-assigned UUID
    expect(remote.logs, isEmpty);                // nothing pushed offline
    expect(await queue.hasPendingCreate(saved.id!), isTrue);
    expect((await cache.readLogs("r1")).single.id, saved.id);
  });

  test('fetchEngineeringLogs offline returns cache', () async {
    final store = InMemoryKeyValueStore();
    final remote = FakeRemote();
    final conn = FakeConnectivityService()..emit(false);
    final queue = SyncQueue(store, "u1");
    final cache = LocalCache(store, "u1");
    await cache.upsertLog(EngineeringLog(
      id: "l1", repoId: "r1", userId: "u1", title: "cached",
      description: "d", type: EngineeringLogType.bug, severity: Severity.medium,
      environment: "e", labels: const [],
    ));
    final manager = SyncManager(remote: remote, queue: queue, cache: cache, connectivity: conn);
    final service = SupabaseService(
      remote: remote, connectivity: conn, cache: cache, queue: queue, syncManager: manager,
    );

    final logs = await service.fetchEngineeringLogs("r1");
    expect(logs.single.title, "cached");
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline/supabase_service_offline_test.dart`
Expected: FAIL — constructor params don't exist yet.

- [ ] **Step 3: Implement OfflineRuntime**

```dart
// lib/app/services/offline/offline_runtime.dart
import 'connectivity_service.dart';
import 'key_value_store.dart';
import 'local_cache.dart';
import 'remote_data_source.dart';
import 'sync_manager.dart';
import 'sync_queue.dart';

/// Composition root for the offline stack. Built once in boot.dart.
class OfflineRuntime {
  OfflineRuntime({
    required this.store,
    required this.remote,
    required this.connectivity,
  });

  static OfflineRuntime? _instance;
  static OfflineRuntime get instance {
    final i = _instance;
    if (i == null) {
      throw StateError("OfflineRuntime not configured. Call configure() in boot.");
    }
    return i;
  }

  static void configure(OfflineRuntime runtime) => _instance = runtime;

  final KeyValueStore store;
  final RemoteDataSource remote;
  final ConnectivityService connectivity;

  final Map<String, SyncQueue> _queues = {};
  final Map<String, LocalCache> _caches = {};
  final Map<String, SyncManager> _managers = {};

  SyncQueue queueFor(String userId) =>
      _queues.putIfAbsent(userId, () => SyncQueue(store, userId));

  LocalCache cacheFor(String userId) =>
      _caches.putIfAbsent(userId, () => LocalCache(store, userId));

  SyncManager managerFor(String userId) => _managers.putIfAbsent(
        userId,
        () => SyncManager(
          remote: remote,
          queue: queueFor(userId),
          cache: cacheFor(userId),
          connectivity: connectivity,
        ),
      );
}
```

- [ ] **Step 4: Rewire SupabaseService**

In `supabase_service.dart`:
- Add `import 'package:uuid/uuid.dart';` and offline imports.
- Add constructor + fields (resolve per-user collaborators lazily via `currentUserId`):

```dart
SupabaseService({
  RemoteDataSource? remote,
  ConnectivityService? connectivity,
  LocalCache? cache,
  SyncQueue? queue,
  SyncManager? syncManager,
})  : _injectedRemote = remote,
      _injectedConnectivity = connectivity,
      _injectedCache = cache,
      _injectedQueue = queue,
      _injectedManager = syncManager;

final RemoteDataSource? _injectedRemote;
final ConnectivityService? _injectedConnectivity;
final LocalCache? _injectedCache;
final SyncQueue? _injectedQueue;
final SyncManager? _injectedManager;
static const _uuid = Uuid();

String get _uid => currentUserId ?? "anon";
RemoteDataSource get _remote => _injectedRemote ?? OfflineRuntime.instance.remote;
ConnectivityService get _connectivity =>
    _injectedConnectivity ?? OfflineRuntime.instance.connectivity;
LocalCache get _cache => _injectedCache ?? OfflineRuntime.instance.cacheFor(_uid);
SyncQueue get _queue => _injectedQueue ?? OfflineRuntime.instance.queueFor(_uid);
SyncManager get _manager =>
    _injectedManager ?? OfflineRuntime.instance.managerFor(_uid);

Future<void> _trySync() async {
  if (_connectivity.isOnline) await _manager.drain();
}
```

- Replace the **read** methods with network-first + timeout + cache fallback:

```dart
Future<List<Repository>> fetchRepositories() async {
  if (!_connectivity.isOnline) return _cache.readRepos();
  try {
    final repos = await _remote.fetchRepositories()
        .timeout(const Duration(seconds: 8));
    await _cache.writeRepos(repos);
    return repos;
  } catch (_) {
    return _cache.readRepos();
  }
}

Future<List<EngineeringLog>> fetchEngineeringLogs(String repoId, {SyncStatus? status}) async {
  if (!_connectivity.isOnline) {
    final cached = await _cache.readLogs(repoId);
    return _filter(cached, status);
  }
  try {
    final logs = await _remote.fetchEngineeringLogs(repoId)
        .timeout(const Duration(seconds: 8));
    await _cache.writeLogs(repoId, logs);
    return _filter(logs, status);
  } catch (_) {
    return _filter(await _cache.readLogs(repoId), status);
  }
}

List<EngineeringLog> _filter(List<EngineeringLog> logs, SyncStatus? status) {
  if (status == null) return logs;
  if (status == SyncStatus.synced) {
    return logs.where((l) => l.syncStatus != SyncStatus.local).toList();
  }
  return logs.where((l) => l.syncStatus == status).toList();
}
```

> Note: `fetchEngineeringLogs` now fetches ALL statuses when online then filters
> client-side, so the cache always holds the full set (needed offline). Apply
> the same network-first+cache pattern to `fetchAttachments` and `fetchLogCounts`
> (compute `LogCounts` from cached logs when offline).

- Replace the **write** methods:

```dart
Future<EngineeringLog> createEngineeringLog(EngineeringLog log) async {
  final withId = log.id == null ? log.copyWith(id: _uuid.v4()) : log;
  await _cache.upsertLog(withId);
  await _queue.enqueue(SyncOperation(
    opId: _uuid.v4(), type: SyncOpType.createLog,
    payload: withId.toSupabaseJson(), createdAt: DateTime.now().toUtc(),
  ));
  await _trySync();
  return withId;
}

Future<EngineeringLog> updateEngineeringLog(EngineeringLog log) async {
  if (log.id == null) {
    throw const SupabaseServiceException("Log must be saved first.");
  }
  await _cache.upsertLog(log);
  await _queue.enqueue(SyncOperation(
    opId: _uuid.v4(), type: SyncOpType.updateLog,
    payload: log.toSupabaseJson(), createdAt: DateTime.now().toUtc(),
  ));
  await _trySync();
  return log;
}

Future<void> deleteEngineeringLog(EngineeringLog log) async {
  final id = log.id;
  if (id == null) return;
  await _cache.removeLog(log);
  if (await _queue.hasPendingCreate(id)) {
    await _queue.cancelCreateFor(id); // never synced — cancel, don't delete
    return;
  }
  await _queue.enqueue(SyncOperation(
    opId: _uuid.v4(), type: SyncOpType.deleteLog,
    payload: {"id": id}, createdAt: DateTime.now().toUtc(),
  ));
  await _trySync();
}

Future<Attachment> uploadScreenshot({required String logId, required File file}) async {
  final attachmentId = _uuid.v4();
  final localPath = await _persistPendingFile(file, attachmentId);
  final attachment = Attachment(id: attachmentId, logId: logId, fileUrl: localPath);
  await _cache.upsertAttachment(attachment);
  await _queue.enqueue(SyncOperation(
    opId: _uuid.v4(), type: SyncOpType.createAttachment,
    payload: attachment.toSupabaseJson(), localFilePath: localPath,
    createdAt: DateTime.now().toUtc(),
  ));
  await _trySync();
  return attachment;
}

Future<Attachment> createAttachment(Attachment attachment) async {
  final withId = attachment.id == null ? Attachment(
    id: _uuid.v4(), logId: attachment.logId, fileUrl: attachment.fileUrl,
  ) : attachment;
  await _cache.upsertAttachment(withId);
  await _queue.enqueue(SyncOperation(
    opId: _uuid.v4(), type: SyncOpType.createAttachment,
    payload: withId.toSupabaseJson(), createdAt: DateTime.now().toUtc(),
  ));
  await _trySync();
  return withId;
}
```

- Add the pending-file helper (uses `path_provider`):

```dart
Future<String> _persistPendingFile(File file, String attachmentId) async {
  final dir = await getApplicationDocumentsDirectory();
  final destDir = Directory("${dir.path}/pending_attachments");
  if (!destDir.existsSync()) destDir.createSync(recursive: true);
  final dest = "${destDir.path}/$attachmentId.png";
  await file.copy(dest);
  return dest;
}
```
(add `import 'package:path_provider/path_provider.dart';`)

- In `signOut()` and `deleteCloudAccountData()`, after clearing the token, also
  clear this user's offline state:

```dart
await _queue.clear();
await _cache.clear();
```

> `markLogSynced` / `markLogFinished` / `saveRepository` / `markRepositorySynced`
> / `deleteRepository` stay online-only — delegate straight to `_remote` (they're
> Layer B / repo ops). If called offline they will throw; the UI disables those
> actions offline (Task 8).

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/offline/`
Expected: PASS (all offline tests).

- [ ] **Step 6: Verify analyze**

Run: `flutter analyze`
Expected: no new errors.

- [ ] **Step 7: Commit**

```bash
git add lib/app/services/offline/offline_runtime.dart lib/app/services/supabase_service.dart test/offline/supabase_service_offline_test.dart
git commit -m "feat(offline): offline-aware SupabaseService (cache reads, queued writes)"
```

---

## Task 7: Boot wiring

**Files:**
- Modify: `lib/bootstrap/boot.dart:40-50` (`_init`)

**Interfaces:**
- Consumes: `OfflineRuntime`, `ConnectivityPlusService`, `SupabaseRemote`, `NyKeyValueStore`.

- [ ] **Step 1: Wire the runtime in `_init`**

```dart
// lib/bootstrap/boot.dart — inside _init(), after SupabaseService.initialize()
import '/app/services/offline/connectivity_service.dart';
import '/app/services/offline/key_value_store.dart';
import '/app/services/offline/offline_runtime.dart';
import '/app/services/offline/remote_data_source.dart';
// ...
Future<void> _init() async {
  await SupabaseService.initialize();

  final connectivity = ConnectivityPlusService();
  await connectivity.start();
  OfflineRuntime.configure(OfflineRuntime(
    store: NyKeyValueStore(),
    remote: SupabaseRemote(),
    connectivity: connectivity,
  ));
}
```

- [ ] **Step 2: Start the current user's SyncManager on sign-in**

In `lib/app/controllers/auth_controller.dart` `listenForSignedIn`, after
`await loadProfile();`, start draining for the signed-in user:

```dart
// inside the authState listener, after loadProfile()
final uid = _supabaseService.currentUserId;
if (uid != null) OfflineRuntime.instance.managerFor(uid).start();
```
(add `import '/app/services/offline/offline_runtime.dart';`)

- [ ] **Step 3: Verify the app builds & boots**

Run: `flutter analyze`
Expected: no errors.
Run: `flutter run` (or your device build). Confirm the app opens to Login/Home
without exceptions.

- [ ] **Step 4: Commit**

```bash
git add lib/bootstrap/boot.dart lib/app/controllers/auth_controller.dart
git commit -m "feat(offline): wire OfflineRuntime + start SyncManager on sign-in"
```

---

## Task 8: UI — offline banner, pending badge, disabled online-only actions, attachment previews

**Files:**
- Create: `lib/resources/widgets/offline_banner.dart`
- Modify: `lib/resources/widgets/main_widget.dart` (wrap shell with banner) OR each authed page's Scaffold — follow existing structure
- Modify: `lib/resources/widgets/log_card.dart` (pending badge)
- Modify: `lib/resources/pages/create_log_page.dart` (disable "Sync GitHub" offline)
- Modify: `lib/resources/pages/add_repository_page.dart` (disable submit offline)
- Modify: `lib/resources/pages/log_detail_page.dart` (attachment preview local/remote; disable sync/close offline)
- Test: `test/offline/offline_banner_test.dart`

**Interfaces:**
- Consumes: `OfflineRuntime.instance.connectivity`, `queueFor(uid).pending`.
- Produces: `class OfflineBanner extends StatelessWidget` (listens to connectivity stream, shows bar when offline).

- [ ] **Step 1: Write a widget test for the banner**

```dart
// test/offline/offline_banner_test.dart
import 'package:bughive/resources/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connectivity_service_test.dart' show FakeConnectivityService;

void main() {
  testWidgets('shows bar when offline, hides when online', (tester) async {
    final conn = FakeConnectivityService()..emit(false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OfflineBanner(connectivity: conn)),
    ));
    await tester.pump();
    expect(find.textContaining("offline"), findsOneWidget);
    conn.emit(true);
    await tester.pump();
    expect(find.textContaining("offline"), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline/offline_banner_test.dart`
Expected: FAIL — `offline_banner.dart` not found.

- [ ] **Step 3: Implement OfflineBanner**

```dart
// lib/resources/widgets/offline_banner.dart
import 'package:flutter/material.dart';
import '/app/services/offline/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.connectivity});

  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      initialData: connectivity.isOnline,
      stream: connectivity.onStatusChange,
      builder: (context, snapshot) {
        final online = snapshot.data ?? true;
        if (online) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: const Color(0xFF3B3321),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: const Text(
            "You're offline — changes will sync when you reconnect.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFE1C16E), fontSize: 12),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Mount the banner in the authed shell**

Read `lib/resources/widgets/main_widget.dart`. Wrap the app body so the banner
sits above the routed content (e.g., a `Column(children: [OfflineBanner(...), Expanded(child: child)])`
in the shell, or add `OfflineBanner` to each authed page's Scaffold `body` top).
Use `OfflineRuntime.instance.connectivity`. Follow the existing widget pattern —
do not restructure navigation.

- [ ] **Step 5: Pending badge on LogCard**

Read `lib/resources/widgets/log_card.dart`. Add an optional `bool pendingSync`
parameter; when true, render a small chip "Pending sync" (reuse the existing
chip/badge style in that file). The caller (RepositoryDetailPage) computes it
from `await OfflineRuntime.instance.queueFor(uid).pendingLogIds()` — pass the
set down and check `pendingIds.contains(log.id)`.

- [ ] **Step 6: Disable online-only actions when offline**

- `create_log_page.dart`: the "Sync GitHub" `FilledButton.onPressed` becomes
  `(_saving || !online) ? null : () => _submit(syncGithub: true)`, where `online`
  comes from a `StreamBuilder<bool>`/listen on `OfflineRuntime.instance.connectivity`.
  Add a hint under the row when offline: "Sync to GitHub when you're back online."
  Keep "Keep Local" always enabled (it now works offline).
- `add_repository_page.dart`: disable the submit button offline with a note
  "Adding a repository needs a connection."
- `log_detail_page.dart`: disable "Sync GitHub" / "Mark finished" / "Close issue"
  offline (same pattern). Delete stays enabled (queues offline).

- [ ] **Step 7: Attachment preview local-or-remote in log_detail_page.dart**

Where saved attachments render (currently likely `Image.network(attachment.fileUrl)`),
branch on whether the url is a local file:

```dart
Widget _attachmentImage(String url) {
  final isLocal = !url.startsWith("http");
  return isLocal
      ? Image.file(File(url), width: 92, height: 92, fit: BoxFit.cover)
      : Image.network(url, width: 92, height: 92, fit: BoxFit.cover);
}
```
(add `import 'dart:io';` if missing)

- [ ] **Step 8: Run tests**

Run: `flutter test test/offline/offline_banner_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: no new errors.

- [ ] **Step 9: Commit**

```bash
git add lib/resources/ test/offline/offline_banner_test.dart
git commit -m "feat(offline): offline banner, pending badge, offline-aware buttons, local attachment previews"
```

---

## Task 9: Manual verification + docs

**Files:**
- Modify: `DEVELOPER.md` (offline-first section)

- [ ] **Step 1: Device smoke test (the exact bug the user hit)**

Build & install, then:
1. Sign in online. Open a repo (loads + caches).
2. Turn WiFi OFF. Confirm: app doesn't stall; banner shows; browse cached logs.
3. Create a log with an image → "Keep Local" → succeeds, shows "Pending sync".
4. Edit it, delete a different cached log — all work offline.
5. Turn WiFi ON. Confirm: queue drains automatically, "Pending sync" clears,
   and **exactly one** copy of the log appears in Supabase (no ghost). Verify in
   Supabase dashboard `engineering_logs` there's a single row with the client id.
6. Repeat create-offline → reconnect a few times; confirm no duplicates ever.

- [ ] **Step 2: Run the full offline test suite**

Run: `flutter test test/offline/`
Expected: all PASS.

- [ ] **Step 3: Update DEVELOPER.md**

Replace the "online-only" statements added earlier with an **Offline-First**
subsection describing: cache + queue layer, client-UUID + upsert idempotency,
Layer A auto / Layer B manual, 8s read timeout, `lib/app/services/offline/`
components. Keep it concise (follow the file's table/heading style).

- [ ] **Step 4: Commit**

```bash
git add DEVELOPER.md
git commit -m "docs: document offline-first architecture"
```

---

## Self-Review Notes (author)

- **Spec coverage:** §3 idempotency → Tasks 4/5/6 (upsert, deterministic path, client UUID, single write path, cancel-create-on-delete). §4 components → Tasks 1–5. §5 flows → Tasks 6 (create/delete) + 5 (drain). §6 UI → Task 8. §7 error handling → Task 6 (8s timeout, cache fallback) + Task 5 (markError/break). §8 deps → Task 1. §9 testing → each task's tests + Task 9 smoke test. All covered.
- **Ghost-log regression** explicitly tested in Task 5 Step 1 ("draining the same createLog op twice yields ONE row").
- **Type consistency:** `RemoteDataSource` method names identical across Tasks 4/5/6 fakes and impl; `SyncOpType` enum stable; `LocalCache`/`SyncQueue` signatures reused verbatim.
- **NyStorage API resolved:** verified `save` / `read<String>` / `delete` against `nylo_support 7.27.2` before execution (Task 2 Step 3 updated accordingly).
```
