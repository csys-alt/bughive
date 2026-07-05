import 'dart:async';

import '/app/controllers/home_controller.dart';
import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/resources/pages/add_repository_page.dart';
import '/resources/pages/profile_page.dart';
import '/resources/pages/repository_detail_page.dart';
import '/resources/widgets/loader_widget.dart';
import '/resources/widgets/repo_card.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class HomePage extends NyStatefulWidget<HomeController> {
  static RouteView path = ("/home", (_) => HomePage());

  HomePage({super.key}) : super(child: () => _HomePageState());
}

class _HomePageState extends NyPage<HomePage> {
  Timer? _clock;
  bool _loading = true;
  String? _error;
  String? _confirmDeleteRepoId;
  User? _profile;
  List<RepositoryWorkspaceItem> _items = const [];

  @override
  get init => () async {
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _items.isNotEmpty) setState(() {});
    });
    await _loadWorkspace();
  };

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadWorkspace() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await widget.controller.loadProfile();
      final items = await widget.controller.loadWorkspace();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _items = items;
        _confirmDeleteRepoId = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  Future<bool> _deleteRepository(Repository repository) async {
    try {
      await widget.controller.deleteRepository(repository);
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return false;
    }
  }

  @override
  Widget view(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadWorkspace,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "BugHive",
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => routeTo(ProfilePage.path),
                          icon: CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF30302E),
                            backgroundImage: _profile?.avatarUrl == null
                                ? null
                                : NetworkImage(_profile!.avatarUrl!),
                            child: _profile?.avatarUrl == null
                                ? const Icon(Icons.person_outline, size: 18)
                                : null,
                          ),
                          tooltip: "Profile",
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF2A2A28),
                            foregroundColor: const Color(0xFFEDECE9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "A quiet workspace for bugs, notes, and GitHub decisions.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFB8B5B0),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  routeTo(
                    AddRepositoryPage.path,
                    onPop: (_) => _loadWorkspace(),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add repository"),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(padding: EdgeInsets.all(32), child: Loader())
              else if (_error != null)
                _StateMessage(title: "Workspace unavailable", message: _error!)
              else if (_items.isEmpty)
                const _StateMessage(
                  title: "No repositories",
                  message: "Add a repository to start capturing logs.",
                )
              else
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _confirmDeleteRepoId == item.repository.id
                          ? Dismissible(
                              key: ValueKey(
                                "confirm-${item.repository.id ?? item.repository.url}",
                              ),
                              direction: DismissDirection.horizontal,
                              background: const _CancelBackground(),
                              secondaryBackground: const _DeleteBackground(),
                              confirmDismiss: (direction) async {
                                if (direction == DismissDirection.startToEnd) {
                                  setState(() => _confirmDeleteRepoId = null);
                                  return false;
                                }
                                await _confirmDeleteRepository(item.repository);
                                return false;
                              },
                              child: RepoCard(
                                repository: item.repository,
                                logs: item.counts.total,
                                draft: item.counts.local,
                                synced: item.counts.synced,
                                confirmDelete: true,
                                onCancelDelete: () =>
                                    setState(() => _confirmDeleteRepoId = null),
                                onTap: () =>
                                    _confirmDeleteRepository(item.repository),
                              ),
                            )
                          : Dismissible(
                              key: ValueKey(
                                item.repository.id ?? item.repository.url,
                              ),
                              direction: DismissDirection.endToStart,
                              background: const _DeleteBackground(),
                              confirmDismiss: (_) async {
                                setState(
                                  () =>
                                      _confirmDeleteRepoId = item.repository.id,
                                );
                                return false;
                              },
                              child: RepoCard(
                                repository: item.repository,
                                logs: item.counts.total,
                                draft: item.counts.local,
                                synced: item.counts.synced,
                                onTap: () {
                                  routeTo(
                                    RepositoryDetailPage.path,
                                    data: item.repository,
                                    onPop: (_) => _loadWorkspace(),
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRepository(Repository repository) async {
    final deleted = await _deleteRepository(repository);
    if (!mounted) return;
    if (deleted) {
      setState(() {
        _items = _items
            .where((repoItem) => repoItem.repository.id != repository.id)
            .toList(growable: false);
      });
    } else {
      setState(() => _confirmDeleteRepoId = null);
    }
  }
}

class _CancelBackground extends StatelessWidget {
  const _CancelBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.close, color: Color(0xFFB8B5B0)),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1D1D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline, color: Color(0xFFFF9A9A)),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final String title;
  final String message;

  const _StateMessage({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30302E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFB8B5B0),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
