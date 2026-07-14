import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/services/supabase_service.dart'
    show LogCounts, SupabaseServiceException, SupabaseService;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

abstract class RemoteDataSource {
  Future<List<Repository>> fetchRepositories();
  Future<List<EngineeringLog>> fetchEngineeringLogs(
    String repoId, {
    SyncStatus? status,
  });
  Future<List<Attachment>> fetchAttachments(String logId);
  Future<LogCounts> fetchLogCounts(String repoId);
  Future<Repository> saveRepository(Repository repository);
  Future<Repository> markRepositorySynced(Repository repository);
  Future<void> deleteRepository(Repository repository);
  Future<EngineeringLog> upsertLog(EngineeringLog log);
  Future<EngineeringLog> markLogSynced({
    required EngineeringLog log,
    required int githubIssueNumber,
  });
  Future<EngineeringLog> markLogFinished(EngineeringLog log);
  Future<void> deleteLog(String logId);
  Future<Attachment> upsertAttachment(Attachment attachment);
  Future<Attachment> uploadScreenshot({
    required String logId,
    required String attachmentId,
    required File file,
  });
}

class SupabaseRemote implements RemoteDataSource {
  supabase.SupabaseClient get _client {
    if (!SupabaseService.isInitialized) {
      throw const SupabaseServiceException("Supabase is not configured.");
    }
    return supabase.Supabase.instance.client;
  }

  String? get _currentUserId => SupabaseService.isInitialized
      ? supabase.Supabase.instance.client.auth.currentSession?.user.id
      : null;

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Future<List<Repository>> fetchRepositories() async {
    final userId = _currentUserId;
    if (userId == null) return const [];

    final response = await _client
        .from("repositories")
        .select()
        .eq("user_id", userId)
        .order("created_at", ascending: false);

    return _rows(response).map(Repository.fromJson).toList();
  }

  @override
  Future<LogCounts> fetchLogCounts(String repoId) async {
    final response = await _client
        .from("engineering_logs")
        .select("id,sync_status,github_issue_number,updated_at,created_at")
        .eq("repo_id", repoId);

    final rows = _rows(response);
    final synced = rows
        .where(
          (row) =>
              SyncStatus.fromValue(row["sync_status"] as String?) !=
              SyncStatus.local,
        )
        .length;

    return LogCounts(
      total: rows.length,
      local: rows.length - synced,
      synced: synced,
      latestGithubSync: _latestGithubSync(
        rows.map(EngineeringLog.fromJson).toList(growable: false),
      ),
    );
  }

  @override
  Future<Repository> saveRepository(Repository repository) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw const SupabaseServiceException("Login is required.");
    }

    final response = await _client
        .from("repositories")
        .upsert(
          repository.copyWith(userId: userId).toSupabaseJson(),
          onConflict: "user_id,github_repo_id",
        )
        .select()
        .single();

    return Repository.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<Repository> markRepositorySynced(Repository repository) async {
    final now = DateTime.now().toUtc();
    if (repository.id == null) return repository.copyWith(lastSync: now);

    final response = await _client
        .from("repositories")
        .update({"last_sync": now.toIso8601String()})
        .eq("id", repository.id!)
        .select()
        .single();

    return Repository.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> deleteRepository(Repository repository) async {
    if (repository.id == null) return;
    await _client.from("repositories").delete().eq("id", repository.id!);
  }

  @override
  Future<List<EngineeringLog>> fetchEngineeringLogs(
    String repoId, {
    SyncStatus? status,
  }) async {
    dynamic query = _client
        .from("engineering_logs")
        .select()
        .eq("repo_id", repoId);

    if (status == SyncStatus.synced) {
      query = query.neq("sync_status", SyncStatus.local.value);
    } else if (status != null) {
      query = query.eq("sync_status", status.value);
    }

    final response = await query.order("created_at", ascending: false);
    return _rows(response).map(EngineeringLog.fromJson).toList();
  }

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
  Future<EngineeringLog> markLogSynced({
    required EngineeringLog log,
    required int githubIssueNumber,
  }) async {
    if (log.id == null) {
      throw const SupabaseServiceException("Log must be saved before sync.");
    }

    final response = await _client
        .from("engineering_logs")
        .update({
          "sync_status": SyncStatus.synced.value,
          "github_issue_number": githubIssueNumber,
          "updated_at": DateTime.now().toUtc().toIso8601String(),
        })
        .eq("id", log.id!)
        .select()
        .single();

    return EngineeringLog.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<EngineeringLog> markLogFinished(EngineeringLog log) async {
    if (log.id == null) {
      throw const SupabaseServiceException("Log must be saved first.");
    }

    final response = await _client
        .from("engineering_logs")
        .update({
          "sync_status": SyncStatus.closed.value,
          "updated_at": DateTime.now().toUtc().toIso8601String(),
        })
        .eq("id", log.id!)
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
  Future<List<Attachment>> fetchAttachments(String logId) async {
    final response = await _client
        .from("attachments")
        .select()
        .eq("log_id", logId)
        .order("created_at", ascending: false);

    return _rows(response).map(Attachment.fromJson).toList();
  }

  @override
  Future<Attachment> uploadScreenshot({
    required String logId,
    required String attachmentId,
    required File file,
  }) async {
    final path = "logs/$logId/$attachmentId.png";
    await _client.storage
        .from("bughive")
        .upload(
          path,
          file,
          fileOptions: const supabase.FileOptions(upsert: true),
        );

    final publicUrl = _client.storage.from("bughive").getPublicUrl(path);
    return upsertAttachment(
      Attachment(id: attachmentId, logId: logId, fileUrl: publicUrl),
    );
  }

  DateTime? _latestGithubSync(List<EngineeringLog> logs) {
    DateTime? latest;
    for (final log in logs) {
      if (log.githubIssueNumber == null) continue;
      final syncedAt = log.updatedAt ?? log.createdAt;
      if (syncedAt == null) continue;
      if (latest == null || syncedAt.isAfter(latest)) latest = syncedAt;
    }
    return latest;
  }
}
