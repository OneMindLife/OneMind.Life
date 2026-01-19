import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/app_exception.dart';

/// Service for authentication operations using Supabase Auth.
/// Replaces the custom SessionService with proper JWT-based auth.
class AuthService {
  final SupabaseClient _client;

  AuthService(this._client);

  /// Get current user ID (works for both anonymous and authenticated users)
  String? get currentUserId {
    final userId = _client.auth.currentUser?.id;
    return userId;
  }

  /// Check if user is signed in (anonymous or authenticated)
  bool get isSignedIn {
    final signedIn = _client.auth.currentUser != null;
    return signedIn;
  }

  /// Check if current user is anonymous
  bool get isAnonymous => _client.auth.currentUser?.isAnonymous ?? true;

  /// Get display name from user metadata
  String? get displayName =>
      _client.auth.currentUser?.userMetadata?['display_name'] as String?;

  /// Sign in anonymously if not already signed in.
  /// Returns the user ID.
  Future<String> ensureSignedIn() async {
    if (_client.auth.currentUser != null) {
      return _client.auth.currentUser!.id;
    }

    final response = await _client.auth.signInAnonymously();
    if (response.user == null) {
      throw AppException.authRequired(
        message: 'Failed to sign in anonymously',
      );
    }
    return response.user!.id;
  }

  /// Update user's display name in metadata
  Future<void> setDisplayName(String name) async {
    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': name}),
    );
  }

  /// Check if user has a display name set
  bool get hasDisplayName => displayName != null && displayName!.isNotEmpty;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign out the current user
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Link anonymous account to email/password (for future account upgrades)
  Future<void> linkWithEmail(String email, String password) async {
    await _client.auth.updateUser(
      UserAttributes(email: email, password: password),
    );
  }
}
