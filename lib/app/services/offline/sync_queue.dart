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
