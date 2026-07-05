import 'dart:io';

import '/app/controllers/log_controller.dart';
import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/resources/widgets/dark_dropdown_field.dart';
import '/resources/widgets/github_label_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class LogDetailArgs {
  final Repository repository;
  final EngineeringLog log;

  const LogDetailArgs({required this.repository, required this.log});
}

class LogDetailPage extends NyStatefulWidget<LogController> {
  static RouteView path = ("/logs/detail", (_) => LogDetailPage());

  LogDetailPage({super.key}) : super(child: () => _LogDetailPageState());
}

class _LogDetailPageState extends NyPage<LogDetailPage> {
  LogDetailArgs? _args;
  late EngineeringLog _log;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _environmentController = TextEditingController();
  EngineeringLogType _type = EngineeringLogType.bug;
  Severity _severity = Severity.medium;
  List<String> _labels = const [];
  List<Attachment> _attachments = const [];
  bool _busy = false;
  bool _editing = false;
  bool _syncingGithub = false;

  @override
  get init => () async {
    _args = widget.controller.data<LogDetailArgs>();
    _log = _args!.log;
    _syncControllers();
    _attachments = await widget.controller.loadAttachments(_log);
  };

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _environmentController.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _titleController.text = _log.title;
    _descriptionController.text = _log.description;
    _environmentController.text = _log.environment;
    _labels = _log.labels;
    _type = _log.type;
    _severity = _log.severity;
  }

  EngineeringLog _editedLog() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      throw Exception("Title is required.");
    }
    return _log.copyWith(
      title: title,
      description: _descriptionController.text.trim(),
      type: _type,
      severity: _severity,
      environment: _environmentController.text.trim(),
      labels: _labels,
    );
  }

  Future<void> _saveEdit() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.controller.updateLog(_editedLog());
      if (!mounted) return;
      setState(() {
        _log = updated;
        _editing = false;
        _busy = false;
      });
      _syncControllers();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _markFinished() async {
    final args = _args;
    if (args == null) return;

    setState(() => _busy = true);
    try {
      final updated = await widget.controller.markFinished(
        repository: args.repository,
        log: _log,
      );
      if (!mounted) return;
      setState(() {
        _log = updated;
        _syncControllers();
        _busy = false;
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _syncGithub() async {
    final args = _args;
    if (args == null) return;

    setState(() {
      _busy = true;
      _syncingGithub = true;
    });
    try {
      if (_editing) {
        _log = await widget.controller.updateLog(_editedLog());
        _editing = false;
        _syncControllers();
      }
      final updated = await widget.controller.retrySync(
        repository: args.repository,
        log: _log,
        attachmentUrls: _attachments
            .map((attachment) => attachment.fileUrl)
            .toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _log = updated;
        _syncControllers();
        _busy = false;
        _syncingGithub = false;
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final paths = result?.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty);
    if (paths == null) return;

    setState(() => _busy = true);
    try {
      final nextAttachments = [..._attachments];
      final existing = nextAttachments.map((item) => item.fileUrl).toSet();
      for (final path in paths) {
        if (existing.contains(path)) continue;
        final attachment = await widget.controller.addAttachment(_log, path);
        nextAttachments.add(attachment);
      }
      if (!mounted) return;
      setState(() {
        _attachments = nextAttachments;
        _busy = false;
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteLog() async {
    final args = _args;
    if (args == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete issue?"),
        content: Text(
          _log.githubIssueNumber == null
              ? "This removes the issue from BugHive."
              : "This closes GitHub issue #${_log.githubIssueNumber}, then removes it from BugHive.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.controller.deleteLog(repository: args.repository, log: _log);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _syncingGithub = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget view(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Issue detail"),
        actions: [
          if (!_log.isClosed)
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (_editing) {
                        _saveEdit();
                      } else {
                        setState(() => _editing = true);
                      }
                    },
              child: Text(_editing ? "Save" : "Edit"),
            ),
        ],
      ),
      body: SafeArea(
        child: Opacity(
          opacity: _log.isClosed ? 0.62 : 1,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              if (_editing)
                TextFormField(
                  controller: _titleController,
                  enabled: !_busy && !_log.isClosed,
                  decoration: const InputDecoration(labelText: "Title"),
                )
              else
                Text(
                  _log.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              const SizedBox(height: 14),
              if (_editing) ...[
                Row(
                  children: [
                    Expanded(
                      child: DarkDropdownField<EngineeringLogType>(
                        label: "Type",
                        value: _type,
                        values: EngineeringLogType.values,
                        text: (value) => value.value,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _type = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DarkDropdownField<Severity>(
                        label: "Severity",
                        value: _severity,
                        values: Severity.values,
                        text: (value) => value.value,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _severity = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Badge(label: _editing ? _type.value : _log.type.value),
                  _Badge(
                    label: _editing ? _severity.value : _log.severity.value,
                  ),
                  if (_syncingGithub)
                    const _SyncingBadge()
                  else
                    _Badge(label: _statusLabel()),
                ],
              ),
              const SizedBox(height: 24),
              _Section(title: "Decision", child: Text(_decisionCopy())),
              _Section(
                title: "Description",
                child: _editing
                    ? TextFormField(
                        controller: _descriptionController,
                        enabled: !_busy && !_log.isClosed,
                        minLines: 4,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      )
                    : Text(_log.description),
              ),
              _Section(
                title: "Image",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ImageGrid(
                      urls: _attachments
                          .map((attachment) => attachment.fileUrl)
                          .toList(growable: false),
                    ),
                    if (_editing) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy || _log.isClosed
                            ? null
                            : _pickAttachment,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text("Add images"),
                      ),
                    ],
                  ],
                ),
              ),
              if (_editing || _log.environment.isNotEmpty)
                _Section(
                  title: "Environment",
                  child: _editing
                      ? TextFormField(
                          controller: _environmentController,
                          enabled: !_busy && !_log.isClosed,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        )
                      : Text(_log.environment),
                ),
              if (_editing || _log.labels.isNotEmpty)
                _Section(
                  title: "Labels",
                  child: _editing
                      ? GithubLabelPicker(
                          selected: _labels,
                          enabled: !_busy && !_log.isClosed,
                          onChanged: (labels) =>
                              setState(() => _labels = labels),
                        )
                      : GithubLabelWrap(labels: _log.labels),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed:
                  _busy || _log.githubIssueNumber == null || _log.isClosed
                  ? null
                  : _markFinished,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text("Close GitHub issue"),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _log.isClosed ? null : _syncGithub,
                    icon: Icon(
                      _syncingGithub ? Icons.hourglass_top : Icons.sync,
                      size: 18,
                    ),
                    label: _syncingGithub
                        ? const _SyncingText(prefix: "Syncing")
                        : Text(
                            _log.githubIssueNumber == null
                                ? "Sync GitHub"
                                : "Sync changes",
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _log.isClosed ? null : _deleteLog,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text("Delete issue"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _decisionCopy() {
    if (_log.githubIssueNumber != null) {
      if (_log.isClosed) {
        return "Closed on GitHub. This issue is locked from editing.";
      }
      return "Synced to GitHub issue #${_log.githubIssueNumber}. Keep editing here, then tap Sync changes to update GitHub.";
    }
    if (_syncingGithub) return "Creating GitHub issue now.";
    if (_log.isSynced) {
      return "Marked clear / finished without creating a GitHub issue.";
    }
    return "Not synced. Decide whether it should become a GitHub issue or should be deleted.";
  }

  String _statusLabel() {
    if (_log.isClosed) return "CLOSED";
    if (_log.githubIssueNumber != null) {
      return "ISSUE #${_log.githubIssueNumber}";
    }
    if (_log.isSynced) return "FINISHED";
    return "NOT SYNCED";
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF30302E)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFFB8B5B0),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.45,
                letterSpacing: -0.1,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> urls;

  const _ImageGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF191919),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30302E)),
        ),
        child: Text(
          "No image attached",
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB8B5B0)),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: urls
          .map((url) => _ImageThumb(url: url))
          .toList(growable: false),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final String url;

  const _ImageThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final value = url;
    final uri = Uri.tryParse(value);
    final localFile = File(value);
    if (!(uri != null && uri.hasScheme && uri.scheme.startsWith("http")) &&
        !localFile.existsSync()) {
      return _MissingImage(label: value);
    }

    final image = uri != null && uri.hasScheme && uri.scheme.startsWith("http")
        ? Image.network(value, fit: BoxFit.cover, errorBuilder: _imageError)
        : Image.file(localFile, fit: BoxFit.cover, errorBuilder: _imageError);

    return GestureDetector(
      onTap: () => _openPreview(context, value),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 110, height: 110, child: image),
      ),
    );
  }

  void _openPreview(BuildContext context, String value) {
    final uri = Uri.tryParse(value);
    final fullImage =
        uri != null && uri.hasScheme && uri.scheme.startsWith("http")
        ? Image.network(value, fit: BoxFit.contain)
        : Image.file(File(value), fit: BoxFit.contain);

    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF0F0F0F),
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: fullImage)),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const _MissingImage(label: "Image unavailable");
  }
}

class _MissingImage extends StatelessWidget {
  final String label;

  const _MissingImage({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30302E)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB8B5B0)),
      ),
    );
  }
}

class _SyncingBadge extends StatelessWidget {
  const _SyncingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const _SyncingText(prefix: "SYNCING"),
    );
  }
}

class _SyncingText extends StatefulWidget {
  final String prefix;

  const _SyncingText({required this.prefix});

  @override
  State<_SyncingText> createState() => _SyncingTextState();
}

class _SyncingTextState extends State<_SyncingText> {
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return false;
      setState(() => _dots = _dots == 3 ? 1 : _dots + 1);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      "${widget.prefix}${"." * _dots}",
      style: const TextStyle(
        color: Color(0xFF9CCBFF),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFEDECE9),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
