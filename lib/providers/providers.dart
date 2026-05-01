import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/l10n/locale_provider.dart';
import '../screens/home_tour/models/home_tour_state.dart';
import '../screens/home_tour/notifiers/home_tour_notifier.dart';
import '../services/services.dart';
import '../services/analytics_service.dart';
import '../services/ab_test_service.dart';
import '../services/tutorial_service.dart';
import '../services/donate_prompt_service.dart';

// =============================================================================
// AUTH SERVICE (JWT-based authentication via Supabase Anonymous Auth)
// =============================================================================

/// Auth service provider - manages Supabase Auth for anonymous and authenticated users
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

/// Current user ID provider - ensures user is signed in (anonymously if needed)
/// Also ensures user has a display name (generates random one if missing).
final currentUserIdProvider = FutureProvider<String>((ref) async {
  final authService = ref.watch(authServiceProvider);
  final userId = await authService.ensureSignedIn();
  // Ensure every user has a display name (e.g. "Brave Fox")
  await authService.ensureDisplayName();
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

/// Affirmation service provider
final affirmationServiceProvider = Provider<AffirmationService>((ref) {
  final client = ref.watch(supabaseProvider);
  return AffirmationService(client);
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

/// Personal code service provider
final personalCodeServiceProvider = Provider<PersonalCodeService>((ref) {
  final client = ref.watch(supabaseProvider);
  return PersonalCodeService(client);
});

/// Billing service provider
/// Note: Requires OAuth authentication (Google/Magic Link), not anonymous auth.
/// Methods will return null/empty if user is not authenticated via OAuth.
final billingServiceProvider = Provider<BillingService>((ref) {
  final client = ref.watch(supabaseProvider);
  return BillingService(client);
});

/// Push notification service provider
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final client = ref.watch(supabaseProvider);
  return PushNotificationService(client);
});

// =============================================================================
// TUTORIAL SERVICE
// =============================================================================

/// Tutorial service provider - tracks tutorial completion state
final tutorialServiceProvider = Provider<TutorialService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TutorialService(prefs);
});

/// Check if user has completed tutorial
final hasCompletedTutorialProvider = Provider<bool>((ref) {
  return ref.watch(tutorialServiceProvider).hasCompletedTutorial;
});

/// Throttles the convergence-reached "Support OneMind" dialog.
final donatePromptServiceProvider = Provider<DonatePromptService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DonatePromptService(prefs);
});

// =============================================================================
// BACKGROUND AUDIO
// =============================================================================

/// Loops bundled background music while the user is in an opted-in chat
/// (currently only the official OneMind chat). User-toggleable via the chat
/// screen overflow menu; preference persists across sessions.
final backgroundAudioServiceProvider = Provider<BackgroundAudioService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = BackgroundAudioService(prefs);
  ref.onDispose(service.dispose);
  return service;
});

/// `bool` state notifier mirroring [BackgroundAudioService.isEnabled] so the
/// overflow-menu toggle rebuilds on change.
class BackgroundAudioEnabledNotifier extends StateNotifier<bool> {
  final BackgroundAudioService _service;
  BackgroundAudioEnabledNotifier(this._service) : super(_service.isEnabled);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _service.setEnabled(enabled);
  }

  Future<void> toggle() => setEnabled(!state);
}

final backgroundAudioEnabledProvider =
    StateNotifierProvider<BackgroundAudioEnabledNotifier, bool>((ref) {
  return BackgroundAudioEnabledNotifier(
    ref.watch(backgroundAudioServiceProvider),
  );
});

// =============================================================================
// HOME TOUR
// =============================================================================

/// Check if user has completed the home screen tour
final hasCompletedHomeTourProvider = Provider<bool>((ref) {
  return ref.watch(tutorialServiceProvider).hasCompletedHomeTour;
});

/// Home tour step notifier — auto-disposed after tour completes
final homeTourNotifierProvider =
    StateNotifierProvider.autoDispose<HomeTourNotifier, HomeTourState>(
  (ref) => HomeTourNotifier(analytics: ref.watch(analyticsServiceProvider)),
);

// =============================================================================
// A/B TEST SERVICE
// =============================================================================

/// A/B test service provider — assigns and persists landing page variants
final abTestServiceProvider = Provider<AbTestService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AbTestService(prefs);
});

// =============================================================================
// JOIN FLOW TRACKING
// =============================================================================

/// Tracks the chat ID that user requested to join via invite link.
/// Used to navigate directly to the chat after tutorial if request was approved.
final pendingJoinChatIdProvider = StateProvider<int?>((ref) => null);
