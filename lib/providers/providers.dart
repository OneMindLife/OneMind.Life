import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/services.dart';
import '../services/analytics_service.dart';

// =============================================================================
// AUTH SERVICE (JWT-based authentication via Supabase Anonymous Auth)
// =============================================================================

/// Auth service provider - manages Supabase Auth for anonymous and authenticated users
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

/// Current user ID provider - ensures user is signed in (anonymously if needed)
final currentUserIdProvider = FutureProvider<String>((ref) async {
  final authService = ref.watch(authServiceProvider);
  final userId = await authService.ensureSignedIn();
  return userId;
});

/// Display name from auth metadata
final authDisplayNameProvider = Provider<String?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.displayName;
});

// =============================================================================
// SUPABASE CLIENT
// =============================================================================

/// Base Supabase client provider
/// Auth is handled automatically via JWT tokens from Supabase Auth
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

/// Chat service provider
final chatServiceProvider = Provider<ChatService>((ref) {
  final client = ref.watch(supabaseProvider);
  return ChatService(client);
});

/// Participant service provider
final participantServiceProvider = Provider<ParticipantService>((ref) {
  final client = ref.watch(supabaseProvider);
  return ParticipantService(client);
});

/// Proposition service provider
final propositionServiceProvider = Provider<PropositionService>((ref) {
  final client = ref.watch(supabaseProvider);
  return PropositionService(client);
});

/// Analytics service provider
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

/// Invite service provider
final inviteServiceProvider = Provider<InviteService>((ref) {
  final client = ref.watch(supabaseProvider);
  return InviteService(client);
});

/// Billing service provider
/// Note: Requires OAuth authentication (Google/Magic Link), not anonymous auth.
/// Methods will return null/empty if user is not authenticated via OAuth.
final billingServiceProvider = Provider<BillingService>((ref) {
  final client = ref.watch(supabaseProvider);
  return BillingService(client);
});
