import 'dart:async';

import '/app/models/user.dart';
import '/app/services/supabase_service.dart';
import 'controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthController extends Controller {
  AuthController({SupabaseService? supabaseService})
    : _supabaseService = supabaseService ?? SupabaseService();

  final SupabaseService _supabaseService;

  bool get isSignedIn => _supabaseService.isSignedIn;

  bool get isOfflineMode => _supabaseService.isOfflineMode;

  Future<User?> loadProfile() async {
    return _supabaseService.loadProfile();
  }

  Future<bool> continueWithGithub() async {
    return _supabaseService.signInWithGithub();
  }

  Future<User?> continueWithoutGithub() async {
    await _supabaseService.startOfflineMode();
    return loadProfile();
  }

  StreamSubscription<supabase.AuthState>? listenForSignedIn(
    Future<void> Function() onSignedIn, {
    void Function(Object error)? onError,
  }) {
    return _supabaseService.authStateChanges?.listen((authState) async {
      if (authState.session == null) return;
      try {
        await loadProfile();
        await onSignedIn();
      } catch (error) {
        onError?.call(error);
      }
    });
  }

  Future<void> signOut() async {
    await _supabaseService.signOut();
  }

  Future<void> eraseLocalData() async {
    await _supabaseService.eraseLocalData();
  }
}
