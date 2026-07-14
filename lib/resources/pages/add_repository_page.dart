import '/app/controllers/github_controller.dart';
import '/app/services/github_service.dart';
import '/app/services/offline/offline_runtime.dart';
import '/resources/widgets/github_reconnect_banner.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:url_launcher/url_launcher.dart';

class AddRepositoryPage extends NyStatefulWidget<GithubController> {
  static RouteView path = ("/repositories/add", (_) => AddRepositoryPage());

  AddRepositoryPage({super.key})
    : super(child: () => _AddRepositoryPageState());
}

class _AddRepositoryPageState extends NyPage<AddRepositoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();

  bool _saving = false;
  String? _error;
  bool _reauthRequired = false;
  bool _online = true;

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  get init => () {
    final conn = OfflineRuntime.instance.connectivity;
    _online = conn.isOnline;
    conn.onStatusChange.listen((online) {
      if (mounted) setState(() => _online = online);
    });
  };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _reauthRequired = false;
    });

    try {
      await widget.controller.addRepository(_urlController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on GithubReauthRequiredException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _reauthRequired = true;
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

  Future<void> _openGithubRepositories() async {
    try {
      final url = await widget.controller.repositoriesPageUrl();
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _error = "Could not open GitHub repositories.");
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Repository")),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "GitHub Repository URL",
                  hintText: "github.com/user/project",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Repository URL is required";
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _openGithubRepositories,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text("Open my GitHub repositories"),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_saving || !_online) ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add, size: 18),
                label: const Text("Add Repository"),
              ),
              if (!_online) ...[
                const SizedBox(height: 8),
                const Text(
                  "Adding a repository needs a connection.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB8B5B0), fontSize: 12),
                ),
              ],
              if (_reauthRequired) ...[
                const SizedBox(height: 16),
                const GithubReconnectBanner(),
              ] else if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFF9A9A),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
