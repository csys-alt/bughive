import 'dart:async';

import '/app/controllers/auth_controller.dart';
import '/resources/pages/home_page.dart';
import '/resources/widgets/loader_widget.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nylo_framework/nylo_framework.dart';

class LoginPage extends NyStatefulWidget<AuthController> {
  static RouteView path = ("/login", (_) => LoginPage());

  LoginPage({super.key}) : super(child: () => _LoginPageState());
}

class _LoginPageState extends NyPage<LoginPage> {
  StreamSubscription? _authSubscription;
  bool _checkingSession = true;
  bool _loading = false;
  String? _error;

  @override
  get init => () async {
    _authSubscription = widget.controller.listenForSignedIn(
      () async {
        if (!mounted) return;
        routeTo(HomePage.path, navigationType: NavigationType.pushAndForgetAll);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _error = error.toString());
      },
    );

    try {
      final profile = await widget.controller.loadProfile();
      if (!mounted || profile == null) return;
      routeTo(HomePage.path, navigationType: NavigationType.pushAndForgetAll);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _checkingSession = false);
      }
    }
  };

  @override
  LoadingStyle get loadingStyle => LoadingStyle.none();

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _continueWithGithub() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final opened = await widget.controller.continueWithGithub();
      if (!opened && mounted) {
        setState(() => _error = "Could not open GitHub login.");
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget view(BuildContext context) {
    final theme = Theme.of(context);

    if (_checkingSession) {
      return const Scaffold(body: SafeArea(child: Loader()));
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "BugHive",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Engineering notes\nfor builders.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFB8B5B0),
                      height: 1.35,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: _loading ? null : _continueWithGithub,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const FaIcon(FontAwesomeIcons.github, size: 18),
                    label: const Text("Continue with GitHub"),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFF9A9A),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
