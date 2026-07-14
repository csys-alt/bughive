import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/app/services/offline/connectivity_service.dart';
import '/app/services/offline/local_cache.dart';
import '/app/services/offline/offline_runtime.dart';
import '/app/services/offline/remote_data_source.dart';
import '/app/services/offline/sync_manager.dart';
import '/app/services/offline/sync_operation.dart';
import '/app/services/offline/sync_queue.dart';
import '/config/app.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:uuid/uuid.dart';

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

  static bool _initialized = false;
  static String? _configurationError;
  static const _secureStorage = FlutterSecureStorage();
  static bool _githubTokenListenerAttached = false;
  static const _uuid = Uuid();

  final RemoteDataSource? _injectedRemote;
  final ConnectivityService? _injectedConnectivity;
  final LocalCache? _injectedCache;
  final SyncQueue? _injectedQueue;
  final SyncManager? _injectedManager;

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

  static String _githubTokenKey(String userId) =>
      "github_provider_token_$userId";

  static bool get isConfigured =>
      AppConfig.supabaseUrl.trim().isNotEmpty &&
      AppConfig.supabasePublishableKey.trim().isNotEmpty;

  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (_initialized) return;
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

  supabase.SupabaseClient get _client {
    if (!_initialized) {
      throw SupabaseServiceException(
        _configurationError ?? "Supabase is not configured.",
      );
    }
    return supabase.Supabase.instance.client;
  }

  supabase.Session? get currentSession {
    if (!_initialized) return null;
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
    if (!_initialized) return null;
    return _client.auth.onAuthStateChange;
  }

  Future<bool> signInWithGithub() async {
    if (!_initialized) {
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

  Future<void> signOut() async {
    final userId = currentUserId;
    // Clear device-side state first so the account is never left signed in
    // on this device, even if the server revocation below fails.
    if (userId != null) {
      await _secureStorage.delete(key: _githubTokenKey(userId));
    }
    await _queue.clear();
    await _cache.clear();
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
  /// the cached GitHub token.
  Future<void> deleteCloudAccountData() async {
    if (!_initialized) return;

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
    await _queue.clear();
    await _cache.clear();
  }

  String? _storagePathFromPublicUrl(String? url) {
    if (url == null) return null;
    const marker = "/storage/v1/object/public/bughive/";
    final index = url.indexOf(marker);
    if (index == -1) return null;
    return url.substring(index + marker.length);
  }

  Future<User?> loadProfile() async {
    final session = currentSession;
    if (session == null) return null;

    final profile = _profileFromSession(session);
    // ponytail: offline returns session-derived profile (no avatar upsert);
    // ceiling: profile row won't be created on first offline launch. Upgrade:
    // queue a profile upsert op the same way logs are queued.
    if (!_connectivity.isOnline) return profile;
    try {
      final response = await _client
          .from("profiles")
          .upsert(profile.toProfileJson(), onConflict: "id")
          .select()
          .single();
      return User.fromJson(Map<String, dynamic>.from(response));
    } catch (_) {
      return profile;
    }
  }

  static const _networkTimeout = Duration(seconds: 8);

  Future<List<Repository>> fetchRepositories() async {
    if (!_connectivity.isOnline) return _cache.readRepos();
    try {
      final repos = await _remote.fetchRepositories().timeout(_networkTimeout);
      await _cache.writeRepos(repos);
      return repos;
    } catch (_) {
      return _cache.readRepos();
    }
  }

  Future<LogCounts> fetchLogCounts(String repoId) async {
    if (!_connectivity.isOnline) {
      return _computeLogCounts(await _cache.readLogs(repoId));
    }
    try {
      return await _remote.fetchLogCounts(repoId).timeout(_networkTimeout);
    } catch (_) {
      return _computeLogCounts(await _cache.readLogs(repoId));
    }
  }

  /// Mirrors SupabaseRemote.fetchLogCounts' field semantics exactly so
  /// online and offline counts always agree.
  LogCounts _computeLogCounts(List<EngineeringLog> logs) {
    final synced =
        logs.where((log) => log.syncStatus != SyncStatus.local).length;
    return LogCounts(
      total: logs.length,
      local: logs.length - synced,
      synced: synced,
      latestGithubSync: _latestGithubSync(logs),
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

  Future<Repository> saveRepository(Repository repository) =>
      _remote.saveRepository(repository);

  Future<Repository> markRepositorySynced(Repository repository) =>
      _remote.markRepositorySynced(repository);

  Future<void> deleteRepository(Repository repository) =>
      _remote.deleteRepository(repository);

  Future<List<EngineeringLog>> fetchEngineeringLogs(
    String repoId, {
    SyncStatus? status,
  }) async {
    if (!_connectivity.isOnline) {
      final cached = await _cache.readLogs(repoId);
      return _filter(cached, status);
    }
    try {
      // Always fetch the full set online so the cache holds everything;
      // filtering happens client-side (also applied to cached reads).
      final logs =
          await _remote.fetchEngineeringLogs(repoId).timeout(_networkTimeout);
      await _cache.writeLogs(repoId, logs);
      return _filter(logs, status);
    } catch (_) {
      return _filter(await _cache.readLogs(repoId), status);
    }
  }

  List<EngineeringLog> _filter(List<EngineeringLog> logs, SyncStatus? status) {
    if (status == null) return logs;
    // ponytail: Open tab reuses SyncStatus.local as sentinel for "not closed";
    // if we add a 4th status later, introduce a separate FilterMode enum.
    if (status == SyncStatus.local) {
      return logs.where((l) => l.syncStatus != SyncStatus.closed).toList();
    }
    return logs.where((l) => l.syncStatus == status).toList();
  }

  Future<EngineeringLog> createEngineeringLog(EngineeringLog log) async {
    final withId = log.id == null ? log.copyWith(id: _uuid.v4()) : log;
    await _cache.upsertLog(withId);
    await _queue.enqueue(SyncOperation(
      opId: _uuid.v4(),
      type: SyncOpType.createLog,
      payload: withId.toSupabaseJson(),
      createdAt: DateTime.now().toUtc(),
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
      opId: _uuid.v4(),
      type: SyncOpType.updateLog,
      payload: log.toSupabaseJson(),
      createdAt: DateTime.now().toUtc(),
    ));
    await _trySync();
    return log;
  }

  Future<EngineeringLog> markLogSynced({
    required EngineeringLog log,
    required int githubIssueNumber,
  }) => _remote.markLogSynced(log: log, githubIssueNumber: githubIssueNumber);

  Future<EngineeringLog> markLogFinished(EngineeringLog log) =>
      _remote.markLogFinished(log);

  Future<void> deleteEngineeringLog(EngineeringLog log) async {
    final id = log.id;
    if (id == null) return;
    await _cache.removeLog(log);
    if (await _queue.hasPendingCreate(id)) {
      // Never synced — cancel the queued create instead of enqueuing a
      // delete that the remote has no row for.
      await _queue.cancelCreateFor(id);
      return;
    }
    await _queue.enqueue(SyncOperation(
      opId: _uuid.v4(),
      type: SyncOpType.deleteLog,
      payload: {"id": id},
      createdAt: DateTime.now().toUtc(),
    ));
    await _trySync();
  }

  Future<Attachment> createAttachment(Attachment attachment) async {
    final withId = attachment.id == null
        ? Attachment(
            id: _uuid.v4(),
            logId: attachment.logId,
            fileUrl: attachment.fileUrl,
          )
        : attachment;
    await _cache.upsertAttachment(withId);
    await _queue.enqueue(SyncOperation(
      opId: _uuid.v4(),
      type: SyncOpType.createAttachment,
      payload: withId.toSupabaseJson(),
      createdAt: DateTime.now().toUtc(),
    ));
    await _trySync();
    return withId;
  }

  Future<List<Attachment>> fetchAttachments(String logId) async {
    if (!_connectivity.isOnline) return _cache.readAttachments(logId);
    try {
      final attachments =
          await _remote.fetchAttachments(logId).timeout(_networkTimeout);
      await _cache.writeAttachments(logId, attachments);
      return attachments;
    } catch (_) {
      return _cache.readAttachments(logId);
    }
  }

  Future<Attachment> uploadScreenshot({
    required String logId,
    required File file,
  }) async {
    final attachmentId = _uuid.v4();
    final localPath = await _persistPendingFile(file, attachmentId);
    final attachment =
        Attachment(id: attachmentId, logId: logId, fileUrl: localPath);
    await _cache.upsertAttachment(attachment);
    await _queue.enqueue(SyncOperation(
      opId: _uuid.v4(),
      type: SyncOpType.createAttachment,
      payload: attachment.toSupabaseJson(),
      localFilePath: localPath,
      createdAt: DateTime.now().toUtc(),
    ));
    await _trySync();
    return attachment;
  }

  Future<String> _persistPendingFile(File file, String attachmentId) async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory("${dir.path}/pending_attachments");
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    final dest = "${destDir.path}/$attachmentId.png";
    await file.copy(dest);
    return dest;
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

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
