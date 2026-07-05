import 'dart:io';

import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/services/supabase_service.dart';
import 'github_controller.dart';
import 'controller.dart';

class LogSyncFailure implements Exception {
  final EngineeringLog localLog;
  final String message;

  const LogSyncFailure({required this.localLog, required this.message});

  @override
  String toString() => message;
}

class LogController extends Controller {
  LogController({
    SupabaseService? supabaseService,
    GithubController? githubController,
  }) : _supabaseService = supabaseService ?? SupabaseService(),
       _githubController = githubController ?? GithubController();

  final SupabaseService _supabaseService;
  final GithubController _githubController;

  Future<List<EngineeringLog>> loadLogs(
    Repository repository, {
    SyncStatus? status,
  }) async {
    if (repository.id == null) return const [];
    return _supabaseService.fetchEngineeringLogs(
      repository.id!,
      status: status,
    );
  }

  Future<EngineeringLog> createLocalLog({
    required Repository repository,
    required String title,
    required EngineeringLogType type,
    required Severity severity,
    required List<String> labels,
    required String environment,
    required String description,
    List<String> attachmentUrls = const [],
  }) async {
    final repoId = repository.id;
    final userId = _supabaseService.currentUserId;
    if (repoId == null) {
      throw const SupabaseServiceException("Repository must be saved first.");
    }
    if (userId == null) {
      throw const SupabaseServiceException("Login is required.");
    }

    final savedLog = await _supabaseService.createEngineeringLog(
      EngineeringLog(
        repoId: repoId,
        userId: userId,
        title: title.trim(),
        description: description.trim(),
        type: type,
        severity: severity,
        environment: environment.trim(),
        labels: labels,
      ),
    );

    for (final attachmentUrl in attachmentUrls) {
      if (attachmentUrl.trim().isNotEmpty) {
        await _saveAttachment(savedLog, attachmentUrl.trim());
      }
    }

    return savedLog;
  }

  Future<EngineeringLog> createAndSyncLog({
    required Repository repository,
    required String title,
    required EngineeringLogType type,
    required Severity severity,
    required List<String> labels,
    required String environment,
    required String description,
    List<String> attachmentUrls = const [],
  }) async {
    final localLog = await createLocalLog(
      repository: repository,
      title: title,
      type: type,
      severity: severity,
      labels: labels,
      environment: environment,
      description: description,
      attachmentUrls: attachmentUrls,
    );

    final attachments = localLog.id == null
        ? const <Attachment>[]
        : await _supabaseService.fetchAttachments(localLog.id!);
    final syncedAttachmentUrls = attachments
        .map((attachment) => attachment.fileUrl)
        .toList(growable: false);

    try {
      return await _githubController.syncLog(
        repository: repository,
        log: localLog,
        attachmentUrls: syncedAttachmentUrls,
      );
    } catch (error) {
      throw LogSyncFailure(localLog: localLog, message: error.toString());
    }
  }

  Future<EngineeringLog> retrySync({
    required Repository repository,
    required EngineeringLog log,
    List<String> attachmentUrls = const [],
  }) {
    return _githubController.syncLog(
      repository: repository,
      log: log,
      attachmentUrls: attachmentUrls,
    );
  }

  Future<EngineeringLog> updateLog(EngineeringLog log) {
    return _supabaseService.updateEngineeringLog(log);
  }

  Future<EngineeringLog> markFinished({
    required Repository repository,
    required EngineeringLog log,
  }) {
    return _githubController.closeIssue(repository: repository, log: log);
  }

  Future<void> deleteLog({
    required Repository repository,
    required EngineeringLog log,
  }) async {
    if (log.githubIssueNumber != null) {
      await _githubController.closeIssue(
        repository: repository,
        log: log,
        stateReason: "not_planned",
        markFinished: false,
      );
    }
    return _supabaseService.deleteEngineeringLog(log);
  }

  Future<List<Attachment>> loadAttachments(EngineeringLog log) {
    if (log.id == null) return Future.value(const []);
    return _supabaseService.fetchAttachments(log.id!);
  }

  Future<Attachment> addAttachment(EngineeringLog log, String value) {
    return _saveAttachment(log, value);
  }

  Future<Attachment> _saveAttachment(EngineeringLog log, String value) async {
    final logId = log.id;
    if (logId == null) {
      throw const SupabaseServiceException("Log must be saved first.");
    }

    final file = File(value);
    if (!_supabaseService.isLocalLog(log) && file.existsSync()) {
      return _supabaseService.uploadScreenshot(logId: logId, file: file);
    }

    return _supabaseService.createAttachment(
      Attachment(logId: logId, fileUrl: value),
    );
  }
}
