import '/app/controllers/auth_controller.dart';
import '/app/models/user.dart';
import '/resources/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:url_launcher/url_launcher.dart';

const _githubRevokeUrl = "https://github.com/settings/applications";

class ProfilePage extends NyStatefulWidget<AuthController> {
  static RouteView path = ("/profile", (_) => ProfilePage());

  ProfilePage({super.key}) : super(child: () => _ProfilePageState());
}

class _ProfilePageState extends NyPage<ProfilePage> {
  User? _user;
  String? _error;

  @override
  get init => () async {
    try {
      final user = await widget.controller.loadProfile();
      if (!mounted) return;
      setState(() => _user = user);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  };

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteAccountDialog(),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await widget.controller.deleteAccount();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!mounted) return;

    routeTo(LoginPage.path, navigationType: NavigationType.pushAndForgetAll);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Account data deleted"),
        content: const Text(
          "Your profile, repositories, logs, and attachments were removed "
          "from Supabase. BugHive still has GitHub authorization on your "
          "account until you revoke it yourself.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Later"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(
                Uri.parse(_githubRevokeUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text("Revoke on GitHub"),
          ),
        ],
      ),
    );
  }

  Future<void> _openGithubProfile(User user) async {
    final url = _githubProfileUrl(user);
    if (url == null) return;
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open GitHub profile.")),
      );
    }
  }

  @override
  Widget view(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;

    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              _Card(child: Text(_error!))
            else if (user == null)
              const Center(child: CircularProgressIndicator())
            else
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: const Color(0xFF30302E),
                          backgroundImage: user.avatarUrl == null
                              ? null
                              : NetworkImage(user.avatarUrl!),
                          child: user.avatarUrl == null
                              ? const Icon(Icons.person_outline, size: 32)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.username ?? "Offline workspace",
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.controller.isOfflineMode
                                    ? "Offline mode"
                                    : "GitHub connected",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFFB8B5B0),
                                ),
                              ),
                              if (_githubProfileUrl(user) != null) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _openGithubProfile(user),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      "Inspect GitHub profile",
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF7FB4FF),
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                              if (!widget.controller.isOfflineMode) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () =>
                                      widget.controller.continueWithGithub(),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      "Reconnect to GitHub",
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF7FB4FF),
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _Info(label: "Joined", value: _joinedDate(user.createdAt)),
                    _Info(label: "User ID", value: user.id ?? "-"),
                    _Info(
                      label: "GitHub ID",
                      value: user.githubId ?? "Not connected",
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _DangerZone(
              children: [
                _DangerButton(
                  onPressed: _deleteAccount,
                  icon: Icons.delete_forever,
                  label: "Delete account & Supabase data",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _joinedDate(DateTime? date) {
    if (date == null) return "Unknown";
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  String? _githubProfileUrl(User user) {
    if (widget.controller.isOfflineMode) return null;
    final username = user.username?.trim();
    if (username == null || username.isEmpty) return null;
    if (username == "Offline workspace") return null;
    return "https://github.com/$username";
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Delete account & Supabase data?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This permanently deletes your profile, repositories, logs, "
            "and attachments from Supabase. This cannot be undone.",
          ),
          const SizedBox(height: 16),
          Text(
            'Type "DELETE" to confirm.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (value) =>
                setState(() => _confirmed = value.trim() == "DELETE"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB42318),
          ),
          child: const Text("Delete permanently"),
        ),
      ],
    );
  }
}

class _DangerZone extends StatelessWidget {
  final List<Widget> children;

  const _DangerZone({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF241818),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6D2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Danger zone",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFFFB4B4),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "This permanently deletes your account data from Database.",
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFFE6A0A0)),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _DangerButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFF9A9A),
          side: const BorderSide(color: Color(0xFFB42318)),
          backgroundColor: const Color(0xFF2D1515),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF30302E)),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;

  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFFB8B5B0),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(value),
        ],
      ),
    );
  }
}
