import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/config/app.dart';
import '/config/storage_keys.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class SupabaseServiceException implements Exception {
  final String message;

  const SupabaseServiceException(this.message);

  @override
  String toString() => message;
}

class LogCounts {
  final int total;
  final int local;
  final int synced;
  final DateTime? latestGithubSync;

  const LogCounts({
    required this.total,
    required this.local,
    required this.synced,
    this.latestGithubSync,
  });
}

class SupabaseService {
  static bool _initialized = false;
  static bool _offlineMode = false;
  static String? _configurationError;
  static const _secureStorage = FlutterSecureStorage();
  static bool _githubTokenListenerAttached = false;

  static String _githubTokenKey(String userId) =>
      "github_provider_token_$userId";

  static bool get isConfigured =>
      AppConfig.supabaseUrl.trim().isNotEmpty &&
      AppConfig.supabasePublishableKey.trim().isNotEmpty;

  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    _offlineMode =
        await NyStorage.read<bool>(
          StorageKeysConfig.offlineMode,
          defaultValue: false,
        ) ??
        false;
    if (_initialized) return;
    if (_offlineMode) return;
    if (!isConfigured) {
      _configurationError =
          "Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env.";
      return;
    }

    final url = normalizeSupabaseUrl(AppConfig.supabaseUrl);
    if (url == null) {
      _configurationError =
          "SUPABASE_URL must be like https://your-project-ref.supabase.co";
      return;
    }

    await supabase.Supabase.initialize(
      url: url,
      publishableKey: AppConfig.supabasePublishableKey.trim(),
      debug: AppConfig.environment != "production",
    );
    _initialized = true;
    _attachGithubTokenListener();
  }

  /// Captures the GitHub provider token the moment it's delivered (only on
  /// the initial SIGNED_IN event after OAuth) and caches it in secure
  /// storage, since Supabase does not restore providerToken on app restart.
  static void _attachGithubTokenListener() {
    if (_githubTokenListenerAttached) return;
    _githubTokenListenerAttached = true;

    supabase.Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) async {
      final session = state.session;
      final token = session?.providerToken;
      if (session == null || token == null || token.isEmpty) return;
      await _secureStorage.write(
        key: _githubTokenKey(session.user.id),
        value: token,
      );
    });
  }

  static String? normalizeSupabaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final withScheme = trimmed.contains("://") ? trimmed : "https://$trimmed";
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) return null;
    return uri.toString();
  }

  bool get isOfflineMode => _offlineMode;

  bool isLocalRepository(Repository repository) => _isLocalId(repository.id);

  bool isLocalLog(EngineeringLog log) => _isLocalId(log.id);

  supabase.SupabaseClient get _client {
    if (!_initialized) {
      throw SupabaseServiceException(
        _configurationError ?? "Supabase is not configured.",
      );
    }
    return supabase.Supabase.instance.client;
  }

  supabase.Session? get currentSession {
    if (_offlineMode || !_initialized) return null;
    return supabase.Supabase.instance.client.auth.currentSession;
  }

  String? get currentUserId => currentSession?.user.id;

  /// The GitHub OAuth access token. Prefers the live Supabase session token
  /// (only present right after sign-in), falling back to the token cached
  /// in secure storage on the initial SIGNED_IN event, since Supabase does
  /// not restore providerToken across app restarts.
  Future<String?> getGithubAccessToken() async {
    final liveToken = currentSession?.providerToken;
    if (liveToken != null && liveToken.isNotEmpty) return liveToken;

    final userId = currentUserId;
    if (userId == null) return null;
    return _secureStorage.read(key: _githubTokenKey(userId));
  }

  Future<void> clearGithubAccessToken() async {
    final userId = currentUserId;
    if (userId == null) return;
    await _secureStorage.delete(key: _githubTokenKey(userId));
  }

  bool get isSignedIn => currentSession != null;

  Stream<supabase.AuthState>? get authStateChanges {
    if (_offlineMode || !_initialized) return null;
    return _client.auth.onAuthStateChange;
  }

  Future<bool> signInWithGithub() async {
    if (!_initialized && !_offlineMode) {
      await initialize();
    }
    if (!_initialized) {
      throw SupabaseServiceException(
        _configurationError ?? "Configure Supabase before login.",
      );
    }

    return _client.auth.signInWithOAuth(
      supabase.OAuthProvider.github,
      redirectTo: AppConfig.githubOAuthRedirectUrl.isEmpty
          ? null
          : AppConfig.githubOAuthRedirectUrl,
      scopes: "repo read:user user:email notifications",
    );
  }

  Future<User> startOfflineMode() async {
    _offlineMode = true;
    await NyStorage.save(StorageKeysConfig.offlineMode, true);
    return _offlineProfile();
  }

  Future<void> signOut() async {
    final userId = currentUserId;
    _offlineMode = false;
    // Clear device-side state first so the account is never left signed in
    // on this device, even if the server revocation below fails.
    await NyStorage.delete(StorageKeysConfig.offlineMode);
    await eraseLocalData();
    if (userId != null) {
      await _secureStorage.delete(key: _githubTokenKey(userId));
    }
    if (!_initialized) return;
    try {
      // Global scope revokes the refresh token server-side across all devices.
      await _client.auth.signOut(scope: supabase.SignOutScope.global);
    } catch (_) {
      // If the server can't be reached (e.g. offline), fall back to a local
      // sign-out so the session is still cleared from this device. A logout
      // that silently leaves a valid session behind is a security hole.
      await _client.auth.signOut(scope: supabase.SignOutScope.local);
    }
  }

  /// Permanently deletes everything this account wrote to Supabase: the
  /// screenshot files in storage (not covered by any FK, so cascades won't
  /// reach them), then the profiles row, which cascades to
  /// repositories/engineering_logs/attachments at the DB level. Also clears
  /// the cached GitHub token and on-device offline caches.
  Future<void> deleteCloudAccountData() async {
    if (_offlineMode || !_initialized) return;

    final userId = currentUserId;
    if (userId == null) return;

    final repoRows = _rows(
      await _client.from("repositories").select("id").eq("user_id", userId),
    );
    final repoIds = repoRows
        .map((row) => row["id"]?.toString())
        .whereType<String>()
        .toList(growable: false);

    final storagePaths = <String>[];
    for (final repoId in repoIds) {
      final logRows = _rows(
        await _client
            .from("engineering_logs")
            .select("id")
            .eq("repo_id", repoId),
      );
      final logIds = logRows
          .map((row) => row["id"]?.toString())
          .whereType<String>()
          .toList(growable: false);

      for (final logId in logIds) {
        final attachmentRows = _rows(
          await _client
              .from("attachments")
              .select("file_url")
              .eq("log_id", logId),
        );
        for (final row in attachmentRows) {
          final path = _storagePathFromPublicUrl(row["file_url"]?.toString());
          if (path != null) storagePaths.add(path);
        }
      }
    }

    if (storagePaths.isNotEmpty) {
      await _client.storage.from("bughive").remove(storagePaths);
    }

    await _client.from("profiles").delete().eq("id", userId);
    await _secureStorage.delete(key: _githubTokenKey(userId));
    await eraseLocalData();
  }

  String? _storagePathFromPublicUrl(String? url) {
    if (url == null) return null;
    const marker = "/storage/v1/object/public/bughive/";
    final index = url.indexOf(marker);
    if (index == -1) return null;
    return url.substring(index + marker.length);
  }

  Future<void> eraseLocalData() async {
    await NyStorage.delete(StorageKeysConfig.offlineMode);
    await NyStorage.delete(StorageKeysConfig.offlineRepositories);
    await NyStorage.delete(StorageKeysConfig.offlineLogs);
    await NyStorage.delete(StorageKeysConfig.offlineAttachments);
    _offlineMode = false;
  }

  Future<User?> loadProfile() async {
    if (_offlineMode) return _offlineProfile();

    final session = currentSession;
    if (session == null) return null;

    final profile = _profileFromSession(session);
    final response = await _client
        .from("profiles")
        .upsert(profile.toProfileJson(), onConflict: "id")
        .select()
        .single();

    return User.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<Repository>> fetchRepositories() async {
    if (_offlineMode) return _localRepositories();

    final userId = currentUserId;
    if (userId == null) return const [];

    final response = await _client
        .from("repositories")
        .select()
        .eq("user_id", userId)
        .order("created_at", ascending: false);

    return [
      ...await _localRepositories(),
      ..._rows(response).map(Repository.fromJson),
    ];
  }

  Future<LogCounts> fetchLogCounts(String repoId) async {
    if (_offlineMode || _isLocalId(repoId)) {
      final rows = (await _localLogs())
          .where((log) => log.repoId == repoId)
          .toList(growable: false);
      final synced = rows.where((log) => log.isSynced).length;
      return LogCounts(
        total: rows.length,
        local: rows.length - synced,
        synced: synced,
        latestGithubSync: _latestGithubSync(rows),
      );
    }

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

  Future<Repository> saveRepository(Repository repository) async {
    if (_offlineMode) {
      final repositories = await _localRepositories();
      final saved = repository.copyWith(
        id: repository.id ?? _localId(),
        userId: "offline",
        createdAt: DateTime.now().toUtc(),
      );
      await _saveLocalRepositories([saved, ...repositories]);
      return saved;
    }

    final userId = currentUserId;
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

  Future<Repository> markRepositorySynced(Repository repository) async {
    final now = DateTime.now().toUtc();
    if (repository.id == null) return repository.copyWith(lastSync: now);

    if (_offlineMode || _isLocalId(repository.id)) {
      final updated = repository.copyWith(lastSync: now);
      final repositories = await _localRepositories();
      await _saveLocalRepositories(
        repositories
            .map((item) => item.id == repository.id ? updated : item)
            .toList(growable: false),
      );
      return updated;
    }

    final response = await _client
        .from("repositories")
        .update({"last_sync": now.toIso8601String()})
        .eq("id", repository.id!)
        .select()
        .single();

    return Repository.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> deleteRepository(Repository repository) async {
    if (repository.id == null) return;

    if (_offlineMode || _isLocalId(repository.id)) {
      final repositories = await _localRepositories();
      final logs = await _localLogs();
      final attachments = await _localAttachments();
      final deletedLogIds = logs
          .where((log) => log.repoId == repository.id)
          .map((log) => log.id)
          .whereType<String>()
          .toSet();
      await _saveLocalRepositories(
        repositories
            .where((item) => item.id != repository.id)
            .toList(growable: false),
      );
      await _saveLocalLogs(
        logs
            .where((log) => log.repoId != repository.id)
            .toList(growable: false),
      );
      await _saveLocalAttachments(
        attachments
            .where((attachment) => !deletedLogIds.contains(attachment.logId))
            .toList(growable: false),
      );
      return;
    }

    await _client.from("repositories").delete().eq("id", repository.id!);
  }

  Future<List<EngineeringLog>> fetchEngineeringLogs(
    String repoId, {
    SyncStatus? status,
  }) async {
    if (_offlineMode || _isLocalId(repoId)) {
      final logs = (await _localLogs())
          .where((log) {
            return log.repoId == repoId &&
                (status == null ||
                    (status == SyncStatus.synced && log.isSynced) ||
                    log.syncStatus == status);
          })
          .toList(growable: false);
      logs.sort((a, b) {
        final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      return logs;
    }

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

  Future<EngineeringLog> createEngineeringLog(EngineeringLog log) async {
    if (_offlineMode || _isLocalId(log.repoId)) {
      final logs = await _localLogs();
      final now = DateTime.now().toUtc();
      final saved = log.copyWith(
        id: _localId(),
        userId: "offline",
        createdAt: now,
        updatedAt: now,
      );
      await _saveLocalLogs([saved, ...logs]);
      return saved;
    }

    final response = await _client
        .from("engineering_logs")
        .insert(log.toSupabaseJson())
        .select()
        .single();

    return EngineeringLog.fromJson(Map<String, dynamic>.from(response));
  }

  Future<EngineeringLog> updateEngineeringLog(EngineeringLog log) async {
    if (log.id == null) {
      throw const SupabaseServiceException("Log must be saved first.");
    }

    if (_offlineMode || _isLocalId(log.id)) {
      final logs = await _localLogs();
      final updated = log.copyWith(updatedAt: DateTime.now().toUtc());
      await _saveLocalLogs(
        logs.map((item) => item.id == log.id ? updated : item).toList(),
      );
      return updated;
    }

    final response = await _client
        .from("engineering_logs")
        .update(log.toSupabaseJson())
        .eq("id", log.id!)
        .select()
        .single();

    return EngineeringLog.fromJson(Map<String, dynamic>.from(response));
  }

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

  Future<EngineeringLog> markLogFinished(EngineeringLog log) async {
    if (log.id == null) {
      throw const SupabaseServiceException("Log must be saved first.");
    }

    if (_offlineMode || _isLocalId(log.id)) {
      final logs = await _localLogs();
      final updated = log.copyWith(
        syncStatus: SyncStatus.closed,
        updatedAt: DateTime.now().toUtc(),
      );
      await _saveLocalLogs(
        logs.map((item) => item.id == log.id ? updated : item).toList(),
      );
      return updated;
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

  Future<void> deleteEngineeringLog(EngineeringLog log) async {
    if (log.id == null) return;

    if (_offlineMode || _isLocalId(log.id)) {
      final logs = await _localLogs();
      final attachments = await _localAttachments();
      await _saveLocalLogs(
        logs.where((item) => item.id != log.id).toList(growable: false),
      );
      await _saveLocalAttachments(
        attachments
            .where((attachment) => attachment.logId != log.id)
            .toList(growable: false),
      );
      return;
    }

    await _client.from("engineering_logs").delete().eq("id", log.id!);
  }

  Future<Attachment> createAttachment(Attachment attachment) async {
    if (_offlineMode || _isLocalId(attachment.logId)) {
      final attachments = await _localAttachments();
      final saved = Attachment(
        id: attachment.id ?? _localId(),
        logId: attachment.logId,
        fileUrl: attachment.fileUrl,
        createdAt: DateTime.now().toUtc(),
      );
      await _saveLocalAttachments([saved, ...attachments]);
      return saved;
    }

    final response = await _client
        .from("attachments")
        .insert(attachment.toSupabaseJson())
        .select()
        .single();

    return Attachment.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<Attachment>> fetchAttachments(String logId) async {
    if (_offlineMode || _isLocalId(logId)) {
      return (await _localAttachments())
          .where((attachment) => attachment.logId == logId)
          .toList(growable: false);
    }

    final response = await _client
        .from("attachments")
        .select()
        .eq("log_id", logId)
        .order("created_at", ascending: false);

    return _rows(response).map(Attachment.fromJson).toList();
  }

  Future<Attachment> uploadScreenshot({
    required String logId,
    required File file,
  }) async {
    final path = "logs/$logId/${DateTime.now().microsecondsSinceEpoch}.png";
    await _client.storage
        .from("bughive")
        .upload(
          path,
          file,
          fileOptions: const supabase.FileOptions(upsert: true),
        );

    final publicUrl = _client.storage.from("bughive").getPublicUrl(path);
    return createAttachment(Attachment(logId: logId, fileUrl: publicUrl));
  }

  User _profileFromSession(supabase.Session session) {
    final metadata = session.user.userMetadata ?? {};
    final username =
        metadata["user_name"] ??
        metadata["preferred_username"] ??
        metadata["login"] ??
        metadata["name"];
    final avatarUrl = metadata["avatar_url"] ?? metadata["picture"];
    final githubId = metadata["provider_id"] ?? metadata["sub"];

    return User.fromJson({
      "id": session.user.id,
      "github_id": githubId?.toString(),
      "username": username?.toString(),
      "avatar_url": avatarUrl?.toString(),
      "created_at": session.user.createdAt,
    });
  }

  User _offlineProfile() {
    return User.fromJson({
      "id": "offline",
      "username": "Offline workspace",
      "github_id": null,
      "avatar_url": null,
      "created_at": DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Repository>> _localRepositories() async {
    final rows =
        await NyStorage.readJson<List>(
          StorageKeysConfig.offlineRepositories,
          defaultValue: const [],
        ) ??
        const [];
    return rows
        .whereType<Map>()
        .map((row) => Repository.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> _saveLocalRepositories(List<Repository> repositories) {
    return NyStorage.saveJson(
      StorageKeysConfig.offlineRepositories,
      repositories.map(_repositoryJson).toList(growable: false),
    );
  }

  Future<List<EngineeringLog>> _localLogs() async {
    final rows =
        await NyStorage.readJson<List>(
          StorageKeysConfig.offlineLogs,
          defaultValue: const [],
        ) ??
        const [];
    return rows
        .whereType<Map>()
        .map((row) => EngineeringLog.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> _saveLocalLogs(List<EngineeringLog> logs) {
    return NyStorage.saveJson(
      StorageKeysConfig.offlineLogs,
      logs.map(_logJson).toList(growable: false),
    );
  }

  Future<List<Attachment>> _localAttachments() async {
    final rows =
        await NyStorage.readJson<List>(
          StorageKeysConfig.offlineAttachments,
          defaultValue: const [],
        ) ??
        const [];
    return rows
        .whereType<Map>()
        .map((row) => Attachment.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> _saveLocalAttachments(List<Attachment> attachments) {
    return NyStorage.saveJson(
      StorageKeysConfig.offlineAttachments,
      attachments.map(_attachmentJson).toList(growable: false),
    );
  }

  Map<String, dynamic> _logJson(EngineeringLog log) => {
    if (log.id != null) "id": log.id,
    "repo_id": log.repoId,
    "user_id": log.userId,
    "title": log.title,
    "description": log.description,
    "type": log.type.value,
    "severity": log.severity.value,
    "environment": log.environment,
    "labels": log.labels,
    "sync_status": log.syncStatus.value,
    "github_issue_number": log.githubIssueNumber,
    "created_at": log.createdAt?.toIso8601String(),
    "updated_at": log.updatedAt?.toIso8601String(),
  };

  Map<String, dynamic> _repositoryJson(Repository repository) => {
    if (repository.id != null) "id": repository.id,
    if (repository.userId != null) "user_id": repository.userId,
    "github_repo_id": repository.githubRepoId,
    "owner": repository.owner,
    "name": repository.name,
    "url": repository.url,
    "last_sync": repository.lastSync?.toIso8601String(),
    "created_at": repository.createdAt?.toIso8601String(),
  };

  Map<String, dynamic> _attachmentJson(Attachment attachment) => {
    if (attachment.id != null) "id": attachment.id,
    "log_id": attachment.logId,
    "file_url": attachment.fileUrl,
    "created_at": attachment.createdAt?.toIso8601String(),
  };

  String _localId() => "local_${DateTime.now().microsecondsSinceEpoch}";

  bool _isLocalId(String? id) => id?.startsWith("local_") ?? false;

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

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
