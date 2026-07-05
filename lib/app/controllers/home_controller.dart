import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/app/services/supabase_service.dart';
import 'controller.dart';

class RepositoryWorkspaceItem {
  final Repository repository;
  final LogCounts counts;

  const RepositoryWorkspaceItem({
    required this.repository,
    required this.counts,
  });
}

class HomeController extends Controller {
  HomeController({SupabaseService? supabaseService})
    : _supabaseService = supabaseService ?? SupabaseService();

  final SupabaseService _supabaseService;

  bool get isSignedIn => _supabaseService.isSignedIn;

  Future<User?> loadProfile() {
    return _supabaseService.loadProfile();
  }

  Future<List<RepositoryWorkspaceItem>> loadWorkspace() async {
    final repositories = await _supabaseService.fetchRepositories();

    return Future.wait(
      repositories.map((repository) async {
        if (repository.id == null) return null;
        final counts = await _supabaseService.fetchLogCounts(repository.id!);
        final lastSync = _latestSync(
          repository.lastSync,
          counts.latestGithubSync,
        );
        return RepositoryWorkspaceItem(
          repository: repository.copyWith(lastSync: lastSync),
          counts: counts,
        );
      }),
    ).then((items) => items.nonNulls.toList(growable: false));
  }

  DateTime? _latestSync(DateTime? repositorySync, DateTime? logSync) {
    if (repositorySync == null) return logSync;
    if (logSync == null) return repositorySync;
    return logSync.isAfter(repositorySync) ? logSync : repositorySync;
  }

  Future<void> deleteRepository(Repository repository) {
    return _supabaseService.deleteRepository(repository);
  }
}
