import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_web_stub.dart' if (dart.library.html) 'analytics_web.dart';

/// Analytics service for tracking user events and behavior.
///
/// Wraps Firebase Analytics with typed methods for OneMind-specific events.
/// All methods fail gracefully if Firebase Analytics is not available.
///
/// GA4 Configuration:
/// - Measurement ID: G-BMGWEGECWY
/// - Data Stream: onemind_app (web) - onemind.life
/// - GA Property: onemindsaas (owned by joel@onemind.life)
class AnalyticsService {
  FirebaseAnalytics? _analytics;
  bool _isAvailable = false;

  AnalyticsService({FirebaseAnalytics? analytics}) {
    try {
      _analytics = analytics ?? FirebaseAnalytics.instance;
      _isAvailable = true;
    } catch (_) {
      _isAvailable = false;
    }
  }

  /// Get the analytics observer for navigation tracking
  /// Returns null if analytics is not available
  FirebaseAnalyticsObserver? get observer {
    if (!_isAvailable || _analytics == null) return null;
    return FirebaseAnalyticsObserver(analytics: _analytics!);
  }

  // ============================================================
  // User Properties
  // ============================================================

  /// Set user ID for tracking across sessions
  Future<void> setUserId(String? userId) async {
    if (!_isAvailable || _analytics == null) return;
    await _analytics!.setUserId(id: userId);
  }

  /// Set user properties for segmentation
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    if (!_isAvailable || _analytics == null) return;
    await _analytics!.setUserProperty(name: name, value: value);
  }

  // ============================================================
  // Chat Events
  // ============================================================

  /// User created a new chat
  Future<void> logChatCreated({
    required String chatId,
    required bool hasAiParticipant,
    required int confirmationRounds,
    required bool autoAdvanceProposing,
    required bool autoAdvanceRating,
  }) async {
    // Firebase Analytics requires string or number values, not booleans
    await _logEvent('chat_created', {
      'chat_id': chatId,
      'has_ai_participant': hasAiParticipant ? 1 : 0,
      'confirmation_rounds': confirmationRounds,
      'auto_advance_proposing': autoAdvanceProposing ? 1 : 0,
      'auto_advance_rating': autoAdvanceRating ? 1 : 0,
    });
  }

  /// User joined an existing chat
  Future<void> logChatJoined({
    required String chatId,
    required String joinMethod, // 'invite_code', 'deep_link', 'direct'
  }) async {
    await _logEvent('chat_joined', {
      'chat_id': chatId,
      'join_method': joinMethod,
    });
  }

  /// User opened a chat
  Future<void> logChatOpened({required String chatId}) async {
    await _logEvent('chat_opened', {'chat_id': chatId});
  }

  /// Home screen first paint. Use [isFirstVisit] to distinguish brand-new
  /// users from returners. Fires once per HomeScreen mount, in initState.
  Future<void> logHomeScreenViewed({required bool isFirstVisit}) async {
    await _logEvent('home_screen_viewed', {
      'is_first_visit': isFirstVisit ? 1 : 0,
    });
  }

  /// First-time auto-join into the official OneMind chat completed.
  /// [succeeded] is false when the chat could not be located or the join
  /// API failed; it still records the attempt for funnel analysis.
  Future<void> logOfficialChatAutoJoined({
    required bool succeeded,
    String? chatId,
  }) async {
    await _logEvent('official_chat_auto_joined', {
      'succeeded': succeeded ? 1 : 0,
      if (chatId != null) 'chat_id': chatId,
    });
  }

  /// User was auto-navigated into the official chat after auto-join.
  /// Distinguishes the new auto-open behavior from a manual chat tap.
  Future<void> logOfficialChatAutoOpened({required String chatId}) async {
    await _logEvent('official_chat_auto_opened', {'chat_id': chatId});
  }

  // ============================================================
  // Round Events
  // ============================================================

  /// User submitted a proposition
  Future<void> logPropositionSubmitted({
    required String chatId,
    required int roundNumber,
    required int contentLength,
  }) async {
    await _logEvent('proposition_submitted', {
      'chat_id': chatId,
      'round_number': roundNumber,
      'content_length': contentLength,
    });
  }

  /// User completed rating all propositions
  Future<void> logRatingCompleted({
    required String chatId,
    required int roundNumber,
    required int propositionsRated,
  }) async {
    await _logEvent('rating_completed', {
      'chat_id': chatId,
      'round_number': roundNumber,
      'propositions_rated': propositionsRated,
    });
  }

  /// Round phase changed
  Future<void> logPhaseChanged({
    required String chatId,
    required int roundNumber,
    required String newPhase, // 'proposing', 'rating', 'completed'
  }) async {
    await _logEvent('phase_changed', {
      'chat_id': chatId,
      'round_number': roundNumber,
      'new_phase': newPhase,
    });
  }

  /// Consensus was reached in a chat
  Future<void> logConsensusReached({
    required String chatId,
    required int totalRounds,
    required int confirmationRounds,
  }) async {
    await _logEvent('consensus_reached', {
      'chat_id': chatId,
      'total_rounds': totalRounds,
      'confirmation_rounds': confirmationRounds,
    });
  }

  // ============================================================
  // Payment Events
  // ============================================================

  /// User started checkout flow
  Future<void> logCheckoutStarted({
    required int credits,
    required double value,
  }) async {
    await _logEvent('checkout_started', {
      'credits': credits,
      'value': value,
      'currency': 'USD',
    });
  }

  /// Purchase completed successfully
  Future<void> logPurchaseCompleted({
    required int credits,
    required double value,
    required String transactionId,
  }) async {
    if (!_isAvailable || _analytics == null) return;
    // Use Firebase's built-in purchase event
    await _analytics!.logPurchase(
      currency: 'USD',
      value: value,
      transactionId: transactionId,
      items: [
        AnalyticsEventItem(
          itemId: 'onemind_credits',
          itemName: 'OneMind Credits',
          quantity: credits,
          price: 0.01,
        ),
      ],
    );
  }

  /// User enabled auto-refill
  Future<void> logAutoRefillEnabled({
    required int threshold,
    required int refillAmount,
  }) async {
    await _logEvent('auto_refill_enabled', {
      'threshold': threshold,
      'refill_amount': refillAmount,
    });
  }

  /// User disabled auto-refill
  Future<void> logAutoRefillDisabled() async {
    await _logEvent('auto_refill_disabled', {});
  }

  // ============================================================
  // Engagement Events
  // ============================================================

  /// User shared an invite code
  Future<void> logInviteShared({
    required String chatId,
    required String shareMethod, // 'copy', 'share_sheet'
  }) async {
    if (!_isAvailable || _analytics == null) return;
    await _analytics!.logShare(
      contentType: 'invite_code',
      itemId: chatId,
      method: shareMethod,
    );
  }

  /// User viewed legal document
  Future<void> logLegalDocViewed({
    required String documentType, // 'privacy_policy', 'terms_of_service'
  }) async {
    await _logEvent('legal_doc_viewed', {
      'document_type': documentType,
    });
  }

  /// User tapped the donate button (outbound click to Stripe payment link)
  Future<void> logDonateClicked({required String source}) async {
    await _logEvent('donate_clicked', {'source': source});
  }

  /// A donate prompt was shown to the user (e.g. convergence-reached dialog).
  Future<void> logDonatePromptShown({required String source}) async {
    await _logEvent('donate_prompt_shown', {'source': source});
  }

  /// The user dismissed a donate prompt without donating.
  Future<void> logDonatePromptDismissed({required String source}) async {
    await _logEvent('donate_prompt_dismissed', {'source': source});
  }

  // ============================================================
  // Landing Page Events
  // ============================================================

  /// Landing page was viewed (A/B test)
  Future<void> logLandingViewed({required String variant}) async {
    await _logEvent('landing_viewed', {'variant': variant});
  }

  /// Landing page CTA was clicked (A/B test)
  Future<void> logLandingCtaClicked({required String variant}) async {
    await _logEvent('landing_cta_clicked', {'variant': variant});
  }

  /// A landing page section scrolled into view
  Future<void> logLandingSectionViewed({
    required String section,
    required String variant,
  }) async {
    await _logEvent('landing_section_viewed', {
      'section': section,
      'variant': variant,
    });
  }

  /// User scrolled to a depth threshold (25/50/75/100)
  Future<void> logLandingScrollDepth({
    required int percent,
    required String variant,
  }) async {
    await _logEvent('landing_scroll_depth', {
      'percent': percent,
      'variant': variant,
    });
  }

  // ============================================================
  // Tutorial Events
  // ============================================================

  /// Play screen was shown to user
  Future<void> logPlayScreenViewed() async {
    await _logEvent('play_screen_viewed', {});
  }

  /// User tapped the play button
  Future<void> logPlayButtonTapped() async {
    await _logEvent('play_button_tapped', {});
  }

  /// User started the tutorial (selected a template)
  Future<void> logTutorialStarted({required String templateKey}) async {
    await _logEvent('tutorial_started', {
      'template': templateKey,
    });
  }

  /// User progressed to a new tutorial step
  Future<void> logTutorialStepCompleted({
    required String stepName,
    required int stepIndex,
  }) async {
    await _logEvent('tutorial_step_completed', {
      'step_name': stepName,
      'step_index': stepIndex,
    });
  }

  /// User completed the full tutorial
  Future<void> logTutorialCompleted({required String templateKey}) async {
    if (!_isAvailable || _analytics == null) return;
    await _analytics!.logTutorialComplete();
    await _logEvent('tutorial_completed', {
      'template': templateKey,
    });
  }

  /// User skipped the tutorial
  Future<void> logTutorialSkipped({required String fromStep}) async {
    await _logEvent('tutorial_skipped', {
      'from_step': fromStep,
    });
  }

  /// Home tour step progressed
  Future<void> logHomeTourStepCompleted({
    required String stepName,
    required int stepIndex,
  }) async {
    await _logEvent('home_tour_step_completed', {
      'step_name': stepName,
      'step_index': stepIndex,
    });
  }

  /// Home tour completed
  Future<void> logHomeTourCompleted() async {
    await _logEvent('home_tour_completed', {});
  }

  // ============================================================
  // Error Events
  // ============================================================

  /// Log an error event (non-fatal)
  Future<void> logError({
    required String errorCode,
    required String errorMessage,
    String? screen,
  }) async {
    await _logEvent('app_error', {
      'error_code': errorCode,
      'error_message': errorMessage.substring(
        0,
        errorMessage.length > 100 ? 100 : errorMessage.length,
      ),
      if (screen != null) 'screen': screen,
    });
  }

  // ============================================================
  // Chat Media Events (video + audio on initial message & convergence cards)
  // ============================================================

  /// Video card entered the viewport. Fires once per widget lifetime.
  /// [source] is `'initial_message'` or `'cycle_winner'`.
  Future<void> logChatVideoImpression({
    required String chatId,
    required String source,
    int? cycleId,
  }) async {
    await _logEvent('chat_video_impression', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
    });
  }

  /// Playback began (either from autoplay or user tap).
  Future<void> logChatVideoStarted({
    required String chatId,
    required String source,
    int? cycleId,
    required bool autoplay,
    required double durationSeconds,
  }) async {
    await _logEvent('chat_video_started', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'autoplay': autoplay ? 1 : 0,
      'duration_seconds': durationSeconds,
    });
  }

  /// Playback crossed a progress milestone (25, 50, or 75 percent).
  /// Use logChatVideoCompleted for 100 percent.
  Future<void> logChatVideoProgress({
    required String chatId,
    required String source,
    int? cycleId,
    required int percent, // 25 | 50 | 75
  }) async {
    await _logEvent('chat_video_progress', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'percent': percent,
    });
  }

  /// Video played through to the end naturally.
  Future<void> logChatVideoCompleted({
    required String chatId,
    required String source,
    int? cycleId,
    required double durationSeconds,
  }) async {
    await _logEvent('chat_video_completed', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'duration_seconds': durationSeconds,
    });
  }

  /// Widget disposed before completion (user scrolled away, closed the screen).
  /// Lets us measure real watch-time distributions.
  Future<void> logChatVideoAbandoned({
    required String chatId,
    required String source,
    int? cycleId,
    required double watchTimeSeconds,
    required int percentWatched, // 0-100
    required double durationSeconds,
  }) async {
    await _logEvent('chat_video_abandoned', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'watch_time_seconds': watchTimeSeconds,
      'percent_watched': percentWatched,
      'duration_seconds': durationSeconds,
    });
  }

  /// User unmuted the video (strong engagement signal).
  Future<void> logChatVideoUnmuted({
    required String chatId,
    required String source,
    int? cycleId,
    required double atSeconds,
  }) async {
    await _logEvent('chat_video_unmuted', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'at_seconds': atSeconds,
    });
  }

  /// User went fullscreen.
  Future<void> logChatVideoFullscreen({
    required String chatId,
    required String source,
    int? cycleId,
    required double atSeconds,
  }) async {
    await _logEvent('chat_video_fullscreen', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'at_seconds': atSeconds,
    });
  }

  /// User tapped the "read aloud" button on an initial-message or convergence card.
  /// [hasPreRecorded] = true if the ElevenLabs MP3 played, false if device TTS fallback.
  Future<void> logChatAudioPlayed({
    required String chatId,
    required String source,
    int? cycleId,
    required bool hasPreRecorded,
  }) async {
    await _logEvent('chat_audio_played', {
      'chat_id': chatId,
      'source': source,
      if (cycleId != null) 'cycle_id': cycleId,
      'has_pre_recorded': hasPreRecorded ? 1 : 0,
    });
  }

  // ============================================================
  // Screen Tracking
  // ============================================================

  /// Log screen view and send a gtag page_view for GA4 web engagement tracking.
  ///
  /// Firebase Analytics sends screen_view events, but GA4 web streams count
  /// page_view events for the "2+ page views" engaged session criterion.
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    if (!_isAvailable || _analytics == null) return;
    await _analytics!.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
    // Send a gtag page_view so GA4 counts route changes toward engagement
    if (kIsWeb) {
      sendWebPageView('/$screenName', screenName);
    }
  }

  // ============================================================
  // Private Helpers
  // ============================================================

  Future<void> _logEvent(
    String name,
    Map<String, Object?> parameters,
  ) async {
    if (!_isAvailable || _analytics == null) return;

    // Filter out null values
    final filteredParams = Map<String, Object>.fromEntries(
      parameters.entries.where((e) => e.value != null).map(
            (e) => MapEntry(e.key, e.value!),
          ),
    );

    await _analytics!.logEvent(name: name, parameters: filteredParams);
  }
}
