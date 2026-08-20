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

      test('logPurchaseCompleted logs purchase event', () async {
        await analyticsService.logPurchaseCompleted(
          credits: 500,
          value: 5.00,
          transactionId: 'txn-abc123',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'purchase',
              parameters: {
                'currency': 'USD',
                'value': 5.00,
                'transaction_id': 'txn-abc123',
                'credits': 500,
              },
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
      test('logInviteShared logs share event', () async {
        await analyticsService.logInviteShared(
          chatId: 'chat-123',
          shareMethod: 'copy',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'share',
              parameters: {
                'content_type': 'invite_code',
                'item_id': 'chat-123',
                'method': 'copy',
              },
            )).called(1);
      });

      test('logInviteDialogShown logs auto flag as 1/0', () async {
        await analyticsService.logInviteDialogShown(
          chatId: 'chat-465',
          auto: true,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'invite_dialog_shown',
              parameters: {'item_id': 'chat-465', 'auto': 1},
            )).called(1);
      });

      test('logInviteDialogDismissed logs had_shared as 1/0', () async {
        await analyticsService.logInviteDialogDismissed(
          chatId: 'chat-465',
          hadShared: false,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'invite_dialog_dismissed',
              parameters: {'item_id': 'chat-465', 'had_shared': 0},
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

      test('logDonateClicked logs source', () async {
        await analyticsService.logDonateClicked(source: 'home_app_bar');

        verify(() => mockAnalytics.logEvent(
              name: 'donate_clicked',
              parameters: {'event_source': 'home_app_bar'},
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

    group('Chat Media Events', () {
      test('logChatVideoImpression logs with cycle_id when provided', () async {
        await analyticsService.logChatVideoImpression(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_impression',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
              },
            )).called(1);
      });

      test('logChatVideoImpression omits cycle_id for initial_message', () async {
        await analyticsService.logChatVideoImpression(
          chatId: 'chat-246',
          source: 'initial_message',
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_impression',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'initial_message',
              },
            )).called(1);
      });

      test('logChatVideoStarted includes autoplay and duration', () async {
        await analyticsService.logChatVideoStarted(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
          autoplay: true,
          durationSeconds: 80.0,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_started',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
                'autoplay': 1,
                'duration_seconds': 80.0,
              },
            )).called(1);
      });

      test('logChatVideoProgress logs milestone percent', () async {
        await analyticsService.logChatVideoProgress(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
          percent: 50,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_progress',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
                'percent': 50,
              },
            )).called(1);
      });

      test('logChatVideoCompleted includes duration', () async {
        await analyticsService.logChatVideoCompleted(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
          durationSeconds: 80.0,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_completed',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
                'duration_seconds': 80.0,
              },
            )).called(1);
      });

      test('logChatVideoAbandoned captures watch time and percent', () async {
        await analyticsService.logChatVideoAbandoned(
          chatId: 'chat-246',
          source: 'initial_message',
          watchTimeSeconds: 12.5,
          percentWatched: 42,
          durationSeconds: 30.0,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_abandoned',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'initial_message',
                'watch_time_seconds': 12.5,
                'percent_watched': 42,
                'duration_seconds': 30.0,
              },
            )).called(1);
      });

      test('logChatVideoUnmuted logs at_seconds', () async {
        await analyticsService.logChatVideoUnmuted(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
          atSeconds: 4.2,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_unmuted',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
                'at_seconds': 4.2,
              },
            )).called(1);
      });

      test('logChatVideoFullscreen logs at_seconds', () async {
        await analyticsService.logChatVideoFullscreen(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
          atSeconds: 10.0,
        );

        verify(() => mockAnalytics.logEvent(
              name: 'chat_video_fullscreen',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
                'at_seconds': 10.0,
              },
            )).called(1);
      });

      test('logChatAudioPlayed flags pre-recorded vs fallback', () async {
        await analyticsService.logChatAudioPlayed(
          chatId: 'chat-246',
          source: 'cycle_winner',
          cycleId: 573,
          hasPreRecorded: true,
        );
        verify(() => mockAnalytics.logEvent(
              name: 'chat_audio_played',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'cycle_winner',
                'cycle_id': 573,
                'has_pre_recorded': 1,
              },
            )).called(1);

        await analyticsService.logChatAudioPlayed(
          chatId: 'chat-246',
          source: 'initial_message',
          hasPreRecorded: false,
        );
        verify(() => mockAnalytics.logEvent(
              name: 'chat_audio_played',
              parameters: {
                'chat_id': 'chat-246',
                'event_source': 'initial_message',
                'has_pre_recorded': 0,
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

    group('Quick-chat funnel', () {
      test('logQuickChatStarted', () async {
        await analyticsService.logQuickChatStarted();
        verify(() => mockAnalytics.logEvent(
            name: 'quick_chat_started', parameters: {})).called(1);
      });

      test('logQuickChatAdvanced', () async {
        await analyticsService.logQuickChatAdvanced();
        verify(() => mockAnalytics.logEvent(
            name: 'quick_chat_advanced', parameters: {})).called(1);
      });

      test('logQuickChatVoteDone', () async {
        await analyticsService.logQuickChatVoteDone();
        verify(() => mockAnalytics.logEvent(
            name: 'quick_chat_vote_done', parameters: {})).called(1);
      });

      test('logQuickChatCreateAnother', () async {
        await analyticsService.logQuickChatCreateAnother();
        verify(() => mockAnalytics.logEvent(
            name: 'quick_chat_create_another', parameters: {})).called(1);
      });

      test('logQuickChatShare logs the source', () async {
        await analyticsService.logQuickChatShare(source: 'invite');
        verify(() => mockAnalytics.logEvent(
              name: 'quick_chat_share',
              parameters: {'event_source': 'invite'},
            )).called(1);
      });

      test('logResultsViewed logs mode, round and quick-chat flag as 1/0',
          () async {
        await analyticsService.logResultsViewed(
          chatId: 'chat-771',
          roundNumber: 2,
          ratingMode: 'matches',
          isQuickChat: true,
        );
        verify(() => mockAnalytics.logEvent(
              name: 'results_viewed',
              parameters: {
                'chat_id': 'chat-771',
                'round_number': 2,
                'rating_mode': 'matches',
                'is_quick_chat': 1,
              },
            )).called(1);
      });

      test('logResultsViewed flags a full-wizard grid view as is_quick_chat=0',
          () async {
        await analyticsService.logResultsViewed(
          chatId: 'chat-772',
          roundNumber: 1,
          ratingMode: 'grid',
          isQuickChat: false,
        );
        verify(() => mockAnalytics.logEvent(
              name: 'results_viewed',
              parameters: {
                'chat_id': 'chat-772',
                'round_number': 1,
                'rating_mode': 'grid',
                'is_quick_chat': 0,
              },
            )).called(1);
      });
    });
  });
}
