import 'dart:async';

import '/app/models/user.dart';
import '/app/services/offline/offline_runtime.dart';
import '/app/services/supabase_service.dart';
import 'controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthController extends Controller {
  AuthController({SupabaseService? supabaseService})
    : _supabaseService = supabaseService ?? SupabaseService();

  final SupabaseService _supabaseService;

  bool get isSignedIn => _supabaseService.isSignedIn;

  Future<User?> loadProfile() async {
    return _supabaseService.loadProfile();
  }

  Future<bool> continueWithGithub() async {
    return _supabaseService.signInWithGithub();
  }

  /// Re-runs the GitHub OAuth flow after a token became invalid. Clears the
  /// known-bad cached token first so a fresh one always replaces it.
  Future<bool> reconnectGithub() async {
    await _supabaseService.clearGithubAccessToken();
    return _supabaseService.signInWithGithub();
  }

  StreamSubscription<supabase.AuthState>? listenForSignedIn(
    Future<void> Function() onSignedIn, {
    void Function(Object error)? onError,
  }) {
    return _supabaseService.authStateChanges?.listen((authState) async {
      if (authState.session == null) return;
      try {
        await loadProfile();
        final uid = _supabaseService.currentUserId;
        if (uid != null) OfflineRuntime.instance.managerFor(uid).start();
        await onSignedIn();
      } catch (error) {
        onError?.call(error);
      }
    });
  }

  Future<void> signOut() async {
    await _supabaseService.signOut();
  }

  Future<void> deleteAccount() async {
    await _supabaseService.deleteCloudAccountData();
    await _supabaseService.signOut();
  }
}
