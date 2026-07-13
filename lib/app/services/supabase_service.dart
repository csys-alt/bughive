import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/config/app.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    final response = await _client
        .from("profiles")
        .upsert(profile.toProfileJson(), onConflict: "id")
        .select()
        .single();

    return User.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<Repository>> fetchRepositories() async {
    final userId = currentUserId;
    if (userId == null) return const [];

    final response = await _client
        .from("repositories")
        .select()
        .eq("user_id", userId)
        .order("created_at", ascending: false);

    return _rows(response).map(Repository.fromJson).toList();
  }

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

  Future<Repository> saveRepository(Repository repository) async {
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
    await _client.from("repositories").delete().eq("id", repository.id!);
  }

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

  Future<EngineeringLog> createEngineeringLog(EngineeringLog log) async {
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
    await _client.from("engineering_logs").delete().eq("id", log.id!);
  }

  Future<Attachment> createAttachment(Attachment attachment) async {
    final response = await _client
        .from("attachments")
        .insert(attachment.toSupabaseJson())
        .select()
        .single();

    return Attachment.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<Attachment>> fetchAttachments(String logId) async {
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
