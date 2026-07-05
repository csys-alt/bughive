import 'package:bughive/app/controllers/github_controller.dart';
import 'package:bughive/app/controllers/log_controller.dart';
import 'package:bughive/app/models/engineering_log.dart';
import 'package:bughive/app/models/repository.dart';
import 'package:bughive/app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'deleting a GitHub log closes issue without marking it finished first',
    () async {
      final supabase = _SupabaseDeleteSpy();
      final github = _GithubControllerSpy();
      final controller = LogController(
        supabaseService: supabase,
        githubController: github,
      );
      final repository = Repository(
        id: 'repo-id',
        githubRepoId: 1,
        owner: 'owner',
        name: 'repo',
        url: 'https://github.com/owner/repo',
      );
      const log = EngineeringLog(
        id: 'log-id',
        repoId: 'repo-id',
        userId: 'user-id',
        title: 'Broken flow',
        description: 'Delete fails',
        type: EngineeringLogType.bug,
        severity: Severity.high,
        environment: 'prod',
        labels: [],
        syncStatus: SyncStatus.synced,
        githubIssueNumber: 42,
      );

      await controller.deleteLog(repository: repository, log: log);

      expect(github.stateReason, 'not_planned');
      expect(github.markFinished, isFalse);
      expect(supabase.deletedLog, same(log));
    },
  );
}

class _GithubControllerSpy extends GithubController {
  String? stateReason;
  bool? markFinished;

  @override
  Future<EngineeringLog> closeIssue({
    required Repository repository,
    required EngineeringLog log,
    String stateReason = 'completed',
    bool markFinished = true,
  }) async {
    this.stateReason = stateReason;
    this.markFinished = markFinished;
    return log;
  }
}

class _SupabaseDeleteSpy extends SupabaseService {
  EngineeringLog? deletedLog;

  @override
  Future<void> deleteEngineeringLog(EngineeringLog log) async {
    deletedLog = log;
  }
}
