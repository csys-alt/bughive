import '/app/controllers/auth_controller.dart';
import 'package:flutter/material.dart';

/// Shown when a GitHub API call fails because the cached token is missing,
/// expired, or lacks a required scope (see GithubReauthRequiredException).
/// Re-running the OAuth flow refreshes the cached token without forcing a
/// full sign-out.
class GithubReconnectBanner extends StatefulWidget {
  const GithubReconnectBanner({super.key});

  @override
  State<GithubReconnectBanner> createState() => _GithubReconnectBannerState();
}

class _GithubReconnectBannerState extends State<GithubReconnectBanner> {
  bool _loading = false;

  Future<void> _reconnect() async {
    setState(() => _loading = true);
    try {
      await AuthController().reconnectGithub();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Finish reconnecting in the browser, then try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
            "GitHub connection needs a refresh",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFFFB4B4),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Your GitHub session expired or is missing permissions. Reconnect to keep syncing.",
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFFE6A0A0)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _reconnect,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text("Reconnect to GitHub"),
            ),
          ),
        ],
      ),
    );
  }
}
