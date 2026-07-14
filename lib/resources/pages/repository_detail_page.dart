import 'dart:async';

import '/app/controllers/log_controller.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/services/github_service.dart';
import '/app/services/offline/offline_runtime.dart';
import '/app/services/supabase_service.dart';
import '/resources/pages/create_log_page.dart';
import '/resources/pages/log_detail_page.dart';
import '/resources/widgets/github_reconnect_banner.dart';
import '/resources/widgets/loader_widget.dart';
import '/resources/widgets/log_card.dart';
import '/resources/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart' hide OfflineBanner;

class RepositoryDetailPage extends NyStatefulWidget<LogController> {
  static RouteView path = ("/repository", (_) => RepositoryDetailPage());

  RepositoryDetailPage({super.key})
    : super(child: () => _RepositoryDetailPageState());
}

class _RepositoryDetailPageState extends NyPage<RepositoryDetailPage> {
  Timer? _clock;
  Repository? _repository;
  SyncStatus? _filter;
  bool _loading = true;
  String? _error;
  String? _syncingId;
  List<EngineeringLog> _logs = const [];
  Set<String> _pendingIds = const {};

  @override
  get init => () async {
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _logs.isNotEmpty) setState(() {});
    });
    _repository = widget.controller.data<Repository>();
    await _loadLogs();
  };

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _error = "Repository not found.";
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final logs = await widget.controller.loadLogs(
        repository,
        status: _filter,
      );
      // Refresh pending ids for the badge.
      final uid = SupabaseService().currentUserId;
      final pendingIds = uid != null
          ? await OfflineRuntime.instance.queueFor(uid).pendingLogIds()
          : const <String>{};
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _pendingIds = pendingIds;
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

  Future<void> _syncLog(EngineeringLog log) async {
    final repository = _repository;
    if (repository == null || log.id == null) return;

    setState(() => _syncingId = log.id);
    try {
      final syncedLog = await widget.controller.retrySync(
        repository: repository,
        log: log,
      );
      if (!mounted) return;
      setState(() {
        _logs = _logs
            .map((item) => item.id == syncedLog.id ? syncedLog : item)
            .toList(growable: false);
        _syncingId = null;
      });
    } on GithubReauthRequiredException catch (error) {
      if (!mounted) return;
      setState(() => _syncingId = null);
      _showReauthSnackBar(error);
    } catch (error) {
      if (!mounted) return;
      setState(() => _syncingId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showReauthSnackBar(GithubReauthRequiredException error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        action: SnackBarAction(
          label: "Reconnect",
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              content: const GithubReconnectBanner(),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget view(BuildContext context) {
    final repository = _repository;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(repository?.name ?? "Repository"),
          bottom: TabBar(
            onTap: (index) {
              _filter = switch (index) {
                1 => SyncStatus.local,
                2 => SyncStatus.closed,
                _ => null,
              };
              _loadLogs();
            },
            tabs: const [
              Tab(text: "All"),
              Tab(text: "Open"),
              Tab(text: "Finished"),
            ],
          ),
        ),
        floatingActionButton: repository == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () {
                  routeTo(
                    CreateLogPage.path,
                    data: repository,
                    onPop: (_) => _loadLogs(),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text("New Log"),
              ),
        body: SafeArea(
          child: Column(
            children: [
              OfflineBanner(connectivity: OfflineRuntime.instance.connectivity),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Loader();
    }

    if (_error != null) {
      return _StateBlock(title: "Logs unavailable", message: _error!);
    }

    if (_logs.isEmpty) {
      return const _StateBlock(
        title: "No logs",
        message: "Create an engineering log for this repository.",
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        itemBuilder: (context, index) {
          final log = _logs[index];
          return LogCard(
            key: ValueKey(log.id ?? log.title),
            log: log,
            onTap: () {
              final repository = _repository;
              if (repository == null) return;
              routeTo(
                LogDetailPage.path,
                data: LogDetailArgs(repository: repository, log: log),
                onPop: (_) => _loadLogs(),
              );
            },
            onSync: _syncingId == log.id || log.isSynced
                ? null
                : () => _syncLog(log),
            pendingSync: _pendingIds.contains(log.id),
          );
        },
        separatorBuilder: (_, index) => const SizedBox(height: 12),
        itemCount: _logs.length,
      ),
    );
  }

}



class _StateBlock extends StatelessWidget {
  final String title;
  final String message;

  const _StateBlock({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
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
        ),
      ],
    );
  }
}
