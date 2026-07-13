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
  Future<void> Function()? beforeUpsertLog;

  @override
  Future<EngineeringLog> upsertLog(EngineeringLog log) async {
    final hook = beforeUpsertLog;
    if (hook != null) {
      beforeUpsertLog = null;
      await hook();
    }
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

  test('coalesces: an op enqueued + drain() requested mid-drain is processed in the same cycle', () async {
    // While applying log-1, simulate SupabaseService.trySync: enqueue a new op
    // and call drain() reentrantly. Coalescing must run a follow-up pass that
    // applies log-2 rather than stranding it.
    remote.beforeUpsertLog = () async {
      await queue.enqueue(_createLogOp("log-2"));
      await manager.drain(); // reentrant — hits the _draining guard
    };
    await queue.enqueue(_createLogOp("log-1"));
    await manager.drain();
    expect(remote.logs.keys.toSet(), {"log-1", "log-2"});
    expect(await queue.count(), 0);
  });
}
