import 'dart:io';

import '/app/controllers/log_controller.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/services/offline/offline_runtime.dart';
import '/resources/widgets/dark_dropdown_field.dart';
import '/resources/widgets/github_label_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CreateLogPage extends NyStatefulWidget<LogController> {
  static RouteView path = ("/logs/create", (_) => CreateLogPage());

  CreateLogPage({super.key}) : super(child: () => _CreateLogPageState());
}

class _CreateLogPageState extends NyPage<CreateLogPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _environmentController = TextEditingController();
  final _descriptionController = TextEditingController();

  Repository? _repository;
  EngineeringLogType _type = EngineeringLogType.bug;
  Severity _severity = Severity.medium;
  List<String> _labels = const [];
  List<String> _attachments = const [];
  bool _saving = false;
  bool _online = true;
  bool _localSavedAfterSyncFailure = false;
  String? _error;
  String? _syncWarning;

  @override
  get init => () {
    _repository = widget.controller.data<Repository>();
    final conn = OfflineRuntime.instance.connectivity;
    _online = conn.isOnline;
    conn.onStatusChange.listen((online) {
      if (mounted) setState(() => _online = online);
    });
  };

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  @override
  void dispose() {
    _titleController.dispose();
    _environmentController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool syncGithub}) async {
    if (!_formKey.currentState!.validate()) return;

    final repository = _repository;
    if (repository == null) {
      setState(() => _error = "Repository not found.");
      return;
    }

    setState(() {
      _saving = true;
      _localSavedAfterSyncFailure = false;
      _error = null;
      _syncWarning = null;
    });

    try {
      if (syncGithub) {
        await widget.controller.createAndSyncLog(
          repository: repository,
          title: _titleController.text,
          type: _type,
          severity: _severity,
          labels: _labels,
          environment: _environmentController.text,
          description: _descriptionController.text,
          attachmentUrls: _attachments,
        );
      } else {
        await widget.controller.createLocalLog(
          repository: repository,
          title: _titleController.text,
          type: _type,
          severity: _severity,
          labels: _labels,
          environment: _environmentController.text,
          description: _descriptionController.text,
          attachmentUrls: _attachments,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LogSyncFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _syncWarning = "Saved. GitHub sync failed: ${error.message}";
        _localSavedAfterSyncFailure = true;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _saving = false;
      });
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final paths = result?.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty);
    if (paths == null) return;
    setState(() {
      _attachments = {..._attachments, ...paths}.toList(growable: false);
    });
  }

  void _removeAttachment(String path) {
    setState(() {
      _attachments = _attachments
          .where((attachment) => attachment != path)
          .toList(growable: false);
    });
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Engineering Log")),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: "Title",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Title is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DarkDropdownField<EngineeringLogType>(
                label: "Type",
                value: _type,
                values: EngineeringLogType.values,
                text: (type) => type.value,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 14),
              DarkDropdownField<Severity>(
                label: "Severity",
                value: _severity,
                values: Severity.values,
                text: (severity) => severity.value,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _severity = value ?? _severity),
              ),
              const SizedBox(height: 14),
              _FieldCard(
                title: "Labels",
                child: GithubLabelPicker(
                  selected: _labels,
                  enabled: !_saving,
                  onChanged: (labels) => setState(() => _labels = labels),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _environmentController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: "Environment",
                  hintText: "Android 16, Flutter 3.x",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Environment is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                minLines: 6,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: "Description",
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Description is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickAttachment,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(
                  _attachments.isEmpty
                      ? "Add images"
                      : "Add more images (${_attachments.length})",
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _attachments
                      .map(
                        (path) => _AttachmentPreview(
                          path: path,
                          onRemove: () => _removeAttachment(path),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _Message(text: _error!, isError: true),
              ],
              if (_syncWarning != null) ...[
                const SizedBox(height: 14),
                _Message(text: _syncWarning!, isError: false),
              ],
              const SizedBox(height: 20),
              if (_localSavedAfterSyncFailure)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Back to Logs"),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _submit(syncGithub: false),
                        child: const Text("Keep Local"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_saving || !_online)
                            ? null
                            : () => _submit(syncGithub: true),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text("Sync GitHub"),
                      ),
                    ),
                  ],
                ),
              if (!_online && !_localSavedAfterSyncFailure) ...[
                const SizedBox(height: 8),
                const Text(
                  "Sync to GitHub when you're back online.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB8B5B0), fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _AttachmentPreview({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(path),
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30302E)),
              ),
              child: const Icon(Icons.broken_image_outlined, size: 18),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xCC191919),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FieldCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30302E)),
      ),
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
          child,
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final bool isError;

  const _Message({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF3A1D1D) : const Color(0xFF3B3321),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFF6D2A2A) : const Color(0xFF6B5722),
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isError ? const Color(0xFFFF9A9A) : const Color(0xFFE1C16E),
          letterSpacing: 0,
        ),
      ),
    );
  }
}
