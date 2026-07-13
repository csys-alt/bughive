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
  bool _redrainRequested = false;

  ValueNotifier<int> get pending => _queue.pending;

  void start() {
    _sub = _connectivity.onStatusChange.listen((online) {
      if (online) drain();
    });
    if (_connectivity.isOnline) drain();
  }

  /// Drains the queue in FIFO order. Each op is removed only after its remote
  /// write is confirmed; a failing op is marked and stops the drain so ordering
  /// (log-before-attachment) is preserved. If another drain is requested while
  /// one is in flight, a follow-up pass runs so an op enqueued mid-drain is
  /// never stranded.
  Future<void> drain() async {
    if (_draining) {
      _redrainRequested = true;
      return;
    }
    _draining = true;
    try {
      do {
        _redrainRequested = false;
        var failed = false;
        for (final op in await _queue.all()) {
          try {
            await _apply(op);
            await _queue.remove(op.opId);
          } catch (error) {
            await _queue.markError(op.opId, error.toString());
            failed = true;
            break;
          }
        }
        if (failed) break; // fail-stop: don't re-loop on a persistent failure
      } while (_redrainRequested);
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
