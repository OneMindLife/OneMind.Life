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
  // Create-Chat Funnel
  // ============================================================
  // `chat_created` (above) fires only on final submit. These track the
  // funnel INTO it so we can see how many open the wizard and where they
  // drop off across the 8 steps.

  /// Create-chat wizard opened (reached step 1). Funnel entry point.
  Future<void> logCreateChatOpened() async {
    await _logEvent('create_chat_opened', {});
  }

  /// A create-chat wizard step became visible. [stepIndex] is 0-based.
  Future<void> logCreateChatStepViewed({
    required int stepIndex,
    required String stepName,
  }) async {
    await _logEvent('create_chat_step_viewed', {
      'step_index': stepIndex,
      'step_name': stepName,
    });
  }

  /// User left the create-chat wizard without completing it.
  Future<void> logCreateChatAbandoned({
    required int lastStepIndex,
    required String lastStepName,
  }) async {
    await _logEvent('create_chat_abandoned', {
      'last_step_index': lastStepIndex,
      'last_step_name': lastStepName,
    });
  }

  // ============================================================
  // Quick-Create Funnel (landing-CTA "/create" flow)
  // ============================================================
  // The wizard funnel above is a SEPARATE entry point. These track the
  // streamlined quick-create flow that "Try it free" lands on, so we can see:
  // reached /create → picked a fork → finished creating → got a result.

  /// Reached /create (the fork-choice screen). Quick-create funnel entry point.
  Future<void> logQuickCreateOpened() async {
    await _logEvent('quick_create_opened', {});
  }

  /// Picked an intent fork. [fork] = 'options' | 'group'.
  Future<void> logQuickCreateForkPicked({required String fork}) async {
    await _logEvent('quick_create_fork_picked', {'fork': fork});
  }

  /// A chat was created from the quick-create flow.
  /// [fork] = 'options' | 'group'; [mode] = 'preview' (solo demo) | 'real'
  /// (shareable); [source] = 'start' | 'skip_test' | 'invite_from_preview'.
  Future<void> logQuickCreateChatCreated({
    required String fork,
    required String mode,
    required String source,
  }) async {
    await _logEvent('quick_create_chat_created', {
      'fork': fork,
      'mode': mode,
      'source': source,
    });
  }

  /// User invoked AI option generation in quick-create — lets us see what
  /// share of creators lean on AI vs type their own.
  /// [source] = 'bulk' (the Generate-options button) | 'row' (per-row ✦ fill).
  Future<void> logQuickCreateOptionsAi({required String source}) async {
    await _logEvent('quick_create_options_ai', {'source': source});
  }

  /// Host ended voting on a quick-create chat (a result was produced).
  Future<void> logQuickCreateVotingEnded() async {
    await _logEvent('quick_create_voting_ended', {});
  }

  // --- Quick-chat in-chat funnel (the sealed single-use loop). Fills the gaps
  // so we can see depth-of-engagement and the "went deeper" signals, not just
  // creation. All gated to quick chats (maxCycles == 1) at the call site. ---

  /// Host manually started a quick chat (waiting → proposing).
  Future<void> logQuickChatStarted() async {
    await _logEvent('quick_chat_started', {});
  }

  // --- Seed dialog (in-chat replacement for the old /create fork screen).
  // shown → the host saw "Already have the options?"; seeded → they supplied
  // options and the chat went straight to voting; dismissed → group ideation
  // (proposing). seeded+dismissed should sum to shown; the split IS the old
  // fork metric, now measured at the moment of truth instead of up front. ---

  Future<void> logSeedDialogShown() async {
    await _logEvent('seed_dialog_shown', {});
  }

  Future<void> logSeedDialogSeeded({required int optionCount}) async {
    await _logEvent('seed_dialog_seeded', {'option_count': optionCount});
  }

  /// [method] records how the dialog was dismissed: `x` (close button),
  /// `group_button` ("Get ideas from the group"), or `barrier_or_back`
  /// (tapped outside / system back). Lets us tell a deliberate group-path
  /// choice from a fast bail without reading.
  Future<void> logSeedDialogDismissed({required String method}) async {
    await _logEvent('seed_dialog_dismissed', {'method': method});
  }

  /// Host manually advanced a quick chat from proposing → voting.
  Future<void> logQuickChatAdvanced() async {
    await _logEvent('quick_chat_advanced', {});
  }

  /// A rater finished voting (matches "Done") — fills the rating-completed gap
  /// that only existed for grid mode.
  Future<void> logQuickChatVoteDone() async {
    await _logEvent('quick_chat_vote_done', {});
  }

  /// "Create a new chat" tapped from a finished quick chat — the loop / went-
  /// deeper signal (they ran the mechanism and want another).
  Future<void> logQuickChatCreateAnother() async {
    await _logEvent('quick_chat_create_another', {});
  }

  /// Share surface opened in a quick chat. [source] = 'invite' (app-bar, recruit
  /// voters) | 'result' (finished chat, share the outcome).
  Future<void> logQuickChatShare({required String source}) async {
    await _logEvent('quick_chat_share', {'event_source': source});
  }

  /// User opened the full ranked results ("See full rankings"). This is the
  /// aha/value-delivered moment — the group's ranked outcome is on screen. It
  /// fires for every chat type via the single `_resolveAndOpenResults` funnel,
  /// so [ratingMode] ('matches' | 'grid') and [isQuickChat] (maxCycles==1)
  /// let us segment quick-chat vs full-wizard results views. [roundNumber]
  /// distinguishes a round-1 result from a round-2+ (post-convergence-on-ramp)
  /// result. Currently un-imported as an Ads conversion — a candidate signal
  /// for the /try-demo paid funnel once it's marked a key event in GA4.
  Future<void> logResultsViewed({
    required String chatId,
    required int roundNumber,
    required String ratingMode,
    required bool isQuickChat,
  }) async {
    await _logEvent('results_viewed', {
      'chat_id': chatId,
      'round_number': roundNumber,
      'rating_mode': ratingMode,
      'is_quick_chat': isQuickChat ? 1 : 0,
    });
  }

  // ============================================================
  // Demo Funnel (hardcoded value-first demo — the new landing CTA target)
  // ============================================================
  // Measures the hypothesis: does dropping people straight into a tap-first
  // demo lift engagement vs. the old fork? demo_opened → voted → completed
  // (saw convergence) → create_clicked (demo → real create flow).

  /// Reached the value-first demo (new landing-CTA entry point).
  Future<void> logDemoOpened() async {
    await _logEvent('demo_opened', {});
  }

  /// Cast a pairwise vote in the demo. [step] = 1-based comparison number.
  Future<void> logDemoVoted({required int step}) async {
    await _logEvent('demo_voted', {'step': step});
  }

  /// Reached the demo's winner reveal (saw the full converge).
  Future<void> logDemoCompleted({required String winner}) async {
    await _logEvent('demo_completed', {'winner': winner});
  }

  /// Tapped "Run this with your own group" after the demo (demo → create).
  Future<void> logDemoCreateClicked() async {
    await _logEvent('demo_create_clicked', {});
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
    // Mirror Firebase's standard purchase shape so GA4 ecommerce reports
    // still pick this up. Routed through _logEvent so web flows via gtag.
    await _logEvent('purchase', {
      'currency': 'USD',
      'value': value,
      'transaction_id': transactionId,
      'credits': credits,
    });
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
    await _logEvent('share', {
      'content_type': 'invite_code',
      'item_id': chatId,
      'method': shareMethod,
    });
  }

  /// The invite-share sheet was shown (auto-opened on quick-create, or opened
  /// from the app bar). Gives us the denominator for the make-or-break cold
  /// funnel ratio: of everyone shown the prompt, what % actually share?
  /// [auto] = true when it auto-popped on chat load, false when user-invoked.
  Future<void> logInviteDialogShown({
    required String chatId,
    required bool auto,
  }) async {
    // Firebase Analytics requires string or number values, not booleans.
    await _logEvent('invite_dialog_shown', {
      'item_id': chatId,
      'auto': auto ? 1 : 0,
    });
  }

  /// The invite-share sheet was closed WITHOUT sharing/copying — the rejection
  /// signal. [hadShared] = true if a share/copy happened earlier in this dialog
  /// (so a dismissal after sharing isn't counted as a walk-away).
  Future<void> logInviteDialogDismissed({
    required String chatId,
    required bool hadShared,
  }) async {
    // Firebase Analytics requires string or number values, not booleans.
    await _logEvent('invite_dialog_dismissed', {
      'item_id': chatId,
      'had_shared': hadShared ? 1 : 0,
    });
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
    await _logEvent('donate_clicked', {'event_source': source});
  }

  /// A donate prompt was shown to the user (e.g. convergence-reached dialog).
  Future<void> logDonatePromptShown({required String source}) async {
    await _logEvent('donate_prompt_shown', {'event_source': source});
  }

  /// The user dismissed a donate prompt without donating.
  Future<void> logDonatePromptDismissed({required String source}) async {
    await _logEvent('donate_prompt_dismissed', {'event_source': source});
  }

  // ============================================================
  // Landing Page Events
  // ============================================================

  /// Landing page was viewed (A/B test)
  Future<void> logLandingViewed({required String variant, String? landingRoute}) async {
    await _logEvent('landing_viewed', {
      'variant': variant,
      if (landingRoute != null) 'landing_route': landingRoute,
    });
  }

  /// Landing page CTA was clicked (A/B test)
  Future<void> logLandingCtaClicked({required String variant, String? landingRoute}) async {
    await _logEvent('landing_cta_clicked', {
      'variant': variant,
      if (landingRoute != null) 'landing_route': landingRoute,
    });
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
    await _logEvent('tutorial_complete', const {});
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
      'event_source': source,
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
      'event_source': source,
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
      'event_source': source,
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
      'event_source': source,
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
      'event_source': source,
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
      'event_source': source,
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
      'event_source': source,
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
      'event_source': source,
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
    // PostHog: on web, events are forwarded to window.posthog inside the
    // window._onemindLogEvent bridge (see sendWebEvent + web/index.html), so
    // there's no Dart-side PostHog call here. (posthog_flutter was removed.)

    // On web, always route through gtag.js. The Firebase Analytics web
    // plugin silently dropped chat/proposition/rating events starting
    // 2026-05-02; gtag is the verified-working pipeline (splash_shown,
    // flutter_loaded, play_button_tapped all flow reliably through it).
    if (kIsWeb) {
      sendWebEvent(name, parameters);
      return;
    }

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
