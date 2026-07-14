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
