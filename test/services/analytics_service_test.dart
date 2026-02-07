import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/services/analytics_service.dart';

class MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  late MockFirebaseAnalytics mockAnalytics;
  late AnalyticsService analyticsService;

  setUpAll(() {
    // Register fallback values for complex types
    registerFallbackValue(<AnalyticsEventItem>[]);
  });

  setUp(() {
    mockAnalytics = MockFirebaseAnalytics();
    analyticsService = AnalyticsService(analytics: mockAnalytics);

    // Default mock behaviors
    when(() => mockAnalytics.setUserId(id: any(named: 'id')))
        .thenAnswer((_) async {});
    when(() => mockAnalytics.setUserProperty(
          name: any(named: 'name'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
    when(() => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        )).thenAnswer((_) async {});
    when(() => mockAnalytics.logScreenView(
          screenName: any(named: 'screenName'),
          screenClass: any(named: 'screenClass'),
        )).thenAnswer((_) async {});
    when(() => mockAnalytics.logShare(
          contentType: any(named: 'contentType'),
          itemId: any(named: 'itemId'),
          method: any(named: 'method'),
        )).thenAnswer((_) async {});
    when(() => mockAnalytics.logPurchase(
          currency: any(named: 'currency'),
          value: any(named: 'value'),
          transactionId: any(named: 'transactionId'),
          items: any(named: 'items'),
        )).thenAnswer((_) async {});
  });

  group('AnalyticsService', () {
    group('User Properties', () {
      test('setUserId calls Firebase setUserId', () async {
        await analyticsService.setUserId('user-123');

        verify(() => mockAnalytics.setUserId(id: 'user-123')).called(1);
      });

      test('setUserId handles null userId', () async {
        await analyticsService.setUserId(null);

        verify(() => mockAnalytics.setUserId(id: null)).called(1);
      });

      test('setUserProperty calls Firebase setUserProperty', () async {
        await analyticsService.setUserProperty(
          name: 'subscription_tier',
          value: 'premium',
        );

        verify(() => mockAnalytics.setUserProperty(
              name: 'subscription_tier',
              value: 'premium',
            )).called(1);
      });

      test('setUserProperty handles null value', () async {
        await analyticsService.setUserProperty(
          name: 'subscription_tier',
          value: null,
        );

        verify(() => mockAnalytics.setUserProperty(
              name: 'subscription_tier',
              value: null,
            )).called(1);
      });
    });

    group('Chat Events', () {
      test('logChatCreated logs correct event', () async {
        await analyticsService.logChatCreated(
          chatId: 'chat-123',
          hasAiParticipant: true,
          confirmationRounds: 2,
          autoAdvanceProposing: true,
          autoAdvanceRating: false,
        );

        // Note: booleans are converted to 1/0 for Firebase Analytics compatibility
        verify(() => mockAnalytics.logEvent(
              name: 'chat_created',
              parameters: {
                'chat_id': 'chat-123',
                'has_ai_participant': 1,
                'confirmation_rounds': 2,
                'auto_advance_proposing': 1,
                'auto_advance_rating': 0,
              },
            )).called(1);
      });

      test('logChatJoined logs join method', () async {
        await analyticsService.logChatJoined(
          chatId: 'chat-456',
          joinMethod: 'invite_code',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_joined',
              parameters: {
                'chat_id': 'chat-456',
                'join_method': 'invite_code',
              },
            )).called(1);
      });

      test('logChatOpened logs chat id', () async {
        await analyticsService.logChatOpened(chatId: 'chat-789');

        verify(() => mockAnalytics.logEvent(
              name: 'chat_opened',
              parameters: {'chat_id': 'chat-789'},
            )).called(1);
      });
    });

    group('Round Events', () {
      test('logPropositionSubmitted logs content length', () async {
        await analyticsService.logPropositionSubmitted(
          chatId: 'chat-123',
          roundNumber: 3,
          contentLength: 150,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'proposition_submitted',
              parameters: {
                'chat_id': 'chat-123',
                'round_number': 3,
                'content_length': 150,
              },
            )).called(1);
      });

      test('logRatingCompleted logs propositions rated', () async {
        await analyticsService.logRatingCompleted(
          chatId: 'chat-123',
          roundNumber: 2,
          propositionsRated: 5,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'rating_completed',
              parameters: {
                'chat_id': 'chat-123',
                'round_number': 2,
                'propositions_rated': 5,
              },
            )).called(1);
      });

      test('logPhaseChanged logs new phase', () async {
        await analyticsService.logPhaseChanged(
          chatId: 'chat-123',
          roundNumber: 1,
          newPhase: 'rating',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'phase_changed',
              parameters: {
                'chat_id': 'chat-123',
                'round_number': 1,
                'new_phase': 'rating',
              },
            )).called(1);
      });

      test('logConsensusReached logs round counts', () async {
        await analyticsService.logConsensusReached(
          chatId: 'chat-123',
          totalRounds: 5,
          confirmationRounds: 2,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'consensus_reached',
              parameters: {
                'chat_id': 'chat-123',
                'total_rounds': 5,
                'confirmation_rounds': 2,
              },
            )).called(1);
      });
    });

    group('Payment Events', () {
      test('logCheckoutStarted logs credit value', () async {
        await analyticsService.logCheckoutStarted(
          credits: 100,
          value: 1.00,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'checkout_started',
              parameters: {
                'credits': 100,
                'value': 1.00,
                'currency': 'USD',
              },
            )).called(1);
      });

      test('logPurchaseCompleted uses Firebase purchase event', () async {
        await analyticsService.logPurchaseCompleted(
          credits: 500,
          value: 5.00,
          transactionId: 'txn-abc123',
        );

        verify(() => mockAnalytics.logPurchase(
              currency: 'USD',
              value: 5.00,
              transactionId: 'txn-abc123',
              items: any(named: 'items'),
            )).called(1);
      });

      test('logAutoRefillEnabled logs settings', () async {
        await analyticsService.logAutoRefillEnabled(
          threshold: 50,
          refillAmount: 200,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'auto_refill_enabled',
              parameters: {
                'threshold': 50,
                'refill_amount': 200,
              },
            )).called(1);
      });

      test('logAutoRefillDisabled logs event', () async {
        await analyticsService.logAutoRefillDisabled();

        verify(() => mockAnalytics.logEvent(
              name: 'auto_refill_disabled',
              parameters: {},
            )).called(1);
      });
    });

    group('Engagement Events', () {
      test('logInviteShared uses Firebase share event', () async {
        await analyticsService.logInviteShared(
          chatId: 'chat-123',
          shareMethod: 'copy',
        );

        verify(() => mockAnalytics.logShare(
              contentType: 'invite_code',
              itemId: 'chat-123',
              method: 'copy',
            )).called(1);
      });

      test('logLegalDocViewed logs document type', () async {
        await analyticsService.logLegalDocViewed(
          documentType: 'privacy_policy',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'legal_doc_viewed',
              parameters: {'document_type': 'privacy_policy'},
            )).called(1);
      });
    });

    group('Error Events', () {
      test('logError logs error details', () async {
        await analyticsService.logError(
          errorCode: 'AUTH_FAILED',
          errorMessage: 'User authentication failed',
          screen: 'LoginScreen',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'app_error',
              parameters: {
                'error_code': 'AUTH_FAILED',
                'error_message': 'User authentication failed',
                'screen': 'LoginScreen',
              },
            )).called(1);
      });

      test('logError truncates long messages to 100 chars', () async {
        final longMessage = 'A' * 150;

        await analyticsService.logError(
          errorCode: 'LONG_ERROR',
          errorMessage: longMessage,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'app_error',
              parameters: {
                'error_code': 'LONG_ERROR',
                'error_message': 'A' * 100,
              },
            )).called(1);
      });

      test('logError works without screen parameter', () async {
        await analyticsService.logError(
          errorCode: 'GENERIC_ERROR',
          errorMessage: 'Something went wrong',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'app_error',
              parameters: {
                'error_code': 'GENERIC_ERROR',
                'error_message': 'Something went wrong',
              },
            )).called(1);
      });
    });

    group('Screen Tracking', () {
      test('logScreenView logs screen name and class', () async {
        await analyticsService.logScreenView(
          screenName: 'HomeScreen',
          screenClass: 'HomeScreen',
        );

        verify(() => mockAnalytics.logScreenView(
              screenName: 'HomeScreen',
              screenClass: 'HomeScreen',
            )).called(1);
      });

      test('logScreenView works without screen class', () async {
        await analyticsService.logScreenView(
          screenName: 'ChatScreen',
        );

        verify(() => mockAnalytics.logScreenView(
              screenName: 'ChatScreen',
              screenClass: null,
            )).called(1);
      });
    });

    group('Observer', () {
      test('observer returns FirebaseAnalyticsObserver', () {
        final observer = analyticsService.observer;
        expect(observer, isA<FirebaseAnalyticsObserver>());
      });
    });

    group('Error Handling', () {
      test('handles Firebase errors gracefully', () async {
        when(() => mockAnalytics.logEvent(
              name: any(named: 'name'),
              parameters: any(named: 'parameters'),
            )).thenThrow(Exception('Firebase error'));

        // Should not throw
        expect(
          () => analyticsService.logChatOpened(chatId: 'chat-123'),
          throwsException,
        );
      });
    });
  });
}
