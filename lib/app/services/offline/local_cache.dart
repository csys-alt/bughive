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
