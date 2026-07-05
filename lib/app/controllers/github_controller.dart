import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/services/github_service.dart';
import '/app/services/supabase_service.dart';
import 'controller.dart';

class GithubController extends Controller {
  GithubController({
    SupabaseService? supabaseService,
    GithubService? githubService,
  }) : _supabaseService = supabaseService ?? SupabaseService(),
       _githubService = githubService ?? GithubService();

  final SupabaseService _supabaseService;
  final GithubService _githubService;

  Future<Repository> addRepository(String repositoryUrl) async {
    if (_supabaseService.isOfflineMode) {
      final metadata = _offlineRepository(repositoryUrl);
      return _supabaseService.saveRepository(metadata);
    }

    final userId = _supabaseService.currentUserId;
    if (userId == null) {
      throw const SupabaseServiceException("Login is required.");
    }

    final metadata = await _githubService.getRepository(
      repositoryUrl,
      accessToken: _supabaseService.currentGithubAccessToken,
    );

    final savedRepository = await _supabaseService.saveRepository(
      Repository(
        userId: userId,
        githubRepoId: metadata.githubRepoId,
        owner: metadata.owner,
        name: metadata.name,
        url: metadata.url,
        createdAt: metadata.createdAt,
      ),
    );
    await _importGithubIssues(savedRepository);
    return _supabaseService.markRepositorySynced(savedRepository);
  }

  Future<String> repositoriesPageUrl() async {
    final profile = await _supabaseService.loadProfile();
    final username = profile?.username;
    if (username == null ||
        username.isEmpty ||
        username == "Offline workspace") {
      return "https://github.com/?tab=repositories";
    }
    return "https://github.com/$username?tab=repositories";
  }

  Repository _offlineRepository(String repositoryUrl) {
    final raw = repositoryUrl.trim();
    final uri = Uri.tryParse(raw.contains("://") ? raw : "https://$raw");
    final parts = uri?.pathSegments.where((part) => part.isNotEmpty).toList();
    if (uri == null ||
        uri.host.toLowerCase() != "github.com" ||
        parts == null ||
        parts.length < 2) {
      throw const GithubServiceException(
        "Enter a valid GitHub repository URL.",
      );
    }

    return Repository(
      userId: "offline",
      githubRepoId: DateTime.now().microsecondsSinceEpoch,
      owner: parts[0],
      name: parts[1],
      url: "https://github.com/${parts[0]}/${parts[1]}",
    );
  }

  Future<EngineeringLog> syncLog({
    required Repository repository,
    required EngineeringLog log,
    List<String> attachmentUrls = const [],
  }) async {
    final accessToken = _supabaseService.currentGithubAccessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const GithubServiceException("GitHub access token is missing.");
    }

    if (_supabaseService.isLocalRepository(repository) ||
        _supabaseService.isLocalLog(log)) {
      final metadata = await _githubService.getRepository(
        repository.url,
        accessToken: accessToken,
      );
      final savedRepository = await _supabaseService.saveRepository(
        Repository(
          githubRepoId: metadata.githubRepoId,
          owner: metadata.owner,
          name: metadata.name,
          url: metadata.url,
          createdAt: metadata.createdAt,
        ),
      );
      final onlineLog = await _supabaseService.createEngineeringLog(
        EngineeringLog(
          repoId: savedRepository.id!,
          userId: _supabaseService.currentUserId!,
          title: log.title,
          description: log.description,
          type: log.type,
          severity: log.severity,
          environment: log.environment,
          labels: log.labels,
        ),
      );
      final syncedAttachmentUrls = await _saveAttachments(
        onlineLog,
        attachmentUrls,
        persistExternalUrls: true,
      );
      final issueNumber = await _githubService.createIssue(
        repository: savedRepository,
        log: onlineLog,
        accessToken: accessToken,
        attachmentUrls: syncedAttachmentUrls,
      );
      final syncedLog = await _supabaseService.markLogSynced(
        log: onlineLog,
        githubIssueNumber: issueNumber,
      );
      await _supabaseService.markRepositorySynced(savedRepository);
      await _supabaseService.deleteEngineeringLog(log);
      return syncedLog;
    }

    final syncedAttachmentUrls = await _saveAttachments(log, attachmentUrls);
    if (log.githubIssueNumber != null) {
      await _githubService.updateIssue(
        repository: repository,
        log: log,
        issueNumber: log.githubIssueNumber!,
        accessToken: accessToken,
        attachmentUrls: syncedAttachmentUrls,
      );
      await _supabaseService.markRepositorySynced(repository);
      return _supabaseService.updateEngineeringLog(log);
    }

    final issueNumber = await _githubService.createIssue(
      repository: repository,
      log: log,
      accessToken: accessToken,
      attachmentUrls: syncedAttachmentUrls,
    );
    final syncedLog = await _supabaseService.markLogSynced(
      log: log,
      githubIssueNumber: issueNumber,
    );
    await _supabaseService.markRepositorySynced(repository);
    return syncedLog;
  }

  Future<EngineeringLog> closeIssue({
    required Repository repository,
    required EngineeringLog log,
    String stateReason = "completed",
  }) async {
    final issueNumber = log.githubIssueNumber;
    if (issueNumber == null) {
      throw const GithubServiceException("Sync to GitHub first.");
    }

    final accessToken = _supabaseService.currentGithubAccessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const GithubServiceException("GitHub access token is missing.");
    }

    await _githubService.closeIssue(
      repository: repository,
      issueNumber: issueNumber,
      accessToken: accessToken,
      stateReason: stateReason,
    );
    return _supabaseService.markLogFinished(log);
  }

  Future<void> _importGithubIssues(Repository repository) async {
    final accessToken = _supabaseService.currentGithubAccessToken;
    if (accessToken == null || accessToken.isEmpty || repository.id == null) {
      return;
    }

    final existing = await _supabaseService.fetchEngineeringLogs(
      repository.id!,
    );
    final existingByNumber = {
      for (final log in existing)
        if (log.githubIssueNumber != null) log.githubIssueNumber!: log,
    };

    final issues = await _githubService.listIssues(
      repository: repository,
      accessToken: accessToken,
    );
    final userId = _supabaseService.currentUserId;
    if (userId == null) return;

    final syncedAt = DateTime.now().toUtc();
    for (final issue in issues) {
      final imported = existingByNumber[issue.number];
      if (imported != null) {
        await _supabaseService.updateEngineeringLog(
          imported.copyWith(
            syncStatus: issue.closed ? SyncStatus.closed : SyncStatus.synced,
            createdAt: issue.createdAt ?? imported.createdAt,
            updatedAt: syncedAt,
          ),
        );
        continue;
      }
      await _supabaseService.createEngineeringLog(
        EngineeringLog(
          repoId: repository.id!,
          userId: userId,
          title: issue.title,
          description: issue.body.isEmpty
              ? "Imported from GitHub."
              : issue.body,
          type: EngineeringLogType.bug,
          severity: Severity.medium,
          environment: "GitHub",
          labels: issue.labels,
          syncStatus: issue.closed ? SyncStatus.closed : SyncStatus.synced,
          githubIssueNumber: issue.number,
          createdAt: issue.createdAt,
          updatedAt: syncedAt,
        ),
      );
    }
  }

  Future<List<String>> _saveAttachments(
    EngineeringLog log,
    List<String> attachmentUrls, {
    bool persistExternalUrls = false,
  }) async {
    final logId = log.id;
    if (logId == null) return const [];

    final savedUrls = <String>[];
    for (final attachmentUrl in attachmentUrls) {
      final value = attachmentUrl.trim();
      if (value.isEmpty) continue;

      final file = File(value);
      if (file.existsSync()) {
        final attachment = await _supabaseService.uploadScreenshot(
          logId: logId,
          file: file,
        );
        savedUrls.add(attachment.fileUrl);
      } else {
        if (persistExternalUrls) {
          await _supabaseService.createAttachment(
            Attachment(logId: logId, fileUrl: value),
          );
        }
        savedUrls.add(value);
      }
    }
    return savedUrls;
  }
}
