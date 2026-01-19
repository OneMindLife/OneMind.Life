import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Analytics service for tracking user events and behavior.
///
/// Wraps Firebase Analytics with typed methods for OneMind-specific events.
/// All methods fail gracefully if Firebase Analytics is not available.
///
/// TODO: Firebase Analytics fails on YOUR_DOMAIN domain. Need to configure:
/// 1. Add YOUR_DOMAIN to GA4 property (G-WZS2WCVXRQ) data stream
/// 2. Or check App Check settings in onemindsaas Firebase project
/// See: https://analytics.google.com → Admin → Data Streams
class AnalyticsService {
  FirebaseAnalytics? _analytics;
  bool _isAvailable = false;

  AnalyticsService({FirebaseAnalytics? analytics}) {
    try {
      _analytics = analytics ?? FirebaseAnalytics.instance;
      _isAvailable = true;
    } catch (e) {
      debugPrint('Firebase Analytics not available: $e');
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
    await _logEvent('chat_created', {
      'chat_id': chatId,
      'has_ai_participant': hasAiParticipant,
      'confirmation_rounds': confirmationRounds,
      'auto_advance_proposing': autoAdvanceProposing,
      'auto_advance_rating': autoAdvanceRating,
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
  // Screen Tracking
  // ============================================================

  /// Log screen view
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    if (!_isAvailable || _analytics == null) return;
    await _analytics!.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
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
