import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/app/services/offline/remote_data_source.dart';
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

  final RemoteDataSource _remote = SupabaseRemote();

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

  Future<List<Repository>> fetchRepositories() => _remote.fetchRepositories();

  Future<LogCounts> fetchLogCounts(String repoId) =>
      _remote.fetchLogCounts(repoId);

  Future<Repository> saveRepository(Repository repository) =>
      _remote.saveRepository(repository);

  Future<Repository> markRepositorySynced(Repository repository) =>
      _remote.markRepositorySynced(repository);

  Future<void> deleteRepository(Repository repository) =>
      _remote.deleteRepository(repository);

  Future<List<EngineeringLog>> fetchEngineeringLogs(
    String repoId, {
    SyncStatus? status,
  }) => _remote.fetchEngineeringLogs(repoId, status: status);

  Future<EngineeringLog> createEngineeringLog(EngineeringLog log) =>
      _remote.upsertLog(log);

  Future<EngineeringLog> updateEngineeringLog(EngineeringLog log) {
    if (log.id == null) {
      throw const SupabaseServiceException("Log must be saved first.");
    }
    return _remote.upsertLog(log);
  }

  Future<EngineeringLog> markLogSynced({
    required EngineeringLog log,
    required int githubIssueNumber,
  }) => _remote.markLogSynced(log: log, githubIssueNumber: githubIssueNumber);

  Future<EngineeringLog> markLogFinished(EngineeringLog log) =>
      _remote.markLogFinished(log);

  Future<void> deleteEngineeringLog(EngineeringLog log) async {
    if (log.id == null) return;
    await _remote.deleteLog(log.id!);
  }

  Future<Attachment> createAttachment(Attachment attachment) =>
      _remote.upsertAttachment(attachment);

  Future<List<Attachment>> fetchAttachments(String logId) =>
      _remote.fetchAttachments(logId);

  Future<Attachment> uploadScreenshot({
    required String logId,
    required File file,
  }) {
    // Temporary: generate an id here until Task 6 introduces UUIDs and moves
    // this id generation into the caller/queue.
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return _remote.uploadScreenshot(logId: logId, attachmentId: id, file: file);
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
