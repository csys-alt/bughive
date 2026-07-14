import 'package:bughive/app/models/engineering_log.dart';
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
