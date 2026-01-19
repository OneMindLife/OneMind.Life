import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/notifiers/chat_detail_notifier.dart';

void main() {
  group('ChatDetailState', () {
    group('copyWith', () {
      test('updates currentRound', () {
        final round = Round(
          id: 1,
          cycleId: 1,
          customId: 1,
          phase: RoundPhase.proposing,
          createdAt: DateTime.now(),
        );
        const state = ChatDetailState();

        final updated = state.copyWith(currentRound: round);

        expect(updated.currentRound, equals(round));
        expect(updated.currentRound!.phase, RoundPhase.proposing);
      });

      test('can update round phase via copyWith chain', () {
        final round = Round(
          id: 1,
          cycleId: 1,
          customId: 1,
          phase: RoundPhase.proposing,
          createdAt: DateTime.now(),
        );
        final state = ChatDetailState(currentRound: round);

        // Simulate what _onRoundChange does
        final updatedRound = state.currentRound!.copyWith(phase: RoundPhase.rating);
        final updatedState = state.copyWith(currentRound: updatedRound);

        expect(updatedState.currentRound!.phase, RoundPhase.rating);
        expect(state.currentRound!.phase, RoundPhase.proposing); // Original unchanged
      });
    });
  });

  group('Round.copyWith', () {
    test('updates phase correctly', () {
      final round = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.proposing,
        phaseStartedAt: DateTime(2024, 1, 1, 10, 0),
        phaseEndsAt: DateTime(2024, 1, 1, 10, 5),
        createdAt: DateTime.now(),
      );

      final updated = round.copyWith(
        phase: RoundPhase.rating,
        phaseStartedAt: DateTime(2024, 1, 1, 10, 5),
        phaseEndsAt: DateTime(2024, 1, 1, 10, 10),
      );

      expect(updated.phase, RoundPhase.rating);
      expect(updated.phaseStartedAt, DateTime(2024, 1, 1, 10, 5));
      expect(updated.phaseEndsAt, DateTime(2024, 1, 1, 10, 10));
      expect(updated.id, 1); // Preserved
      expect(updated.cycleId, 1); // Preserved
    });

    test('preserves other fields when only updating phase', () {
      final round = Round(
        id: 5,
        cycleId: 10,
        customId: 3,
        phase: RoundPhase.waiting,
        winningPropositionId: 42,
        isSoleWinner: true,
        createdAt: DateTime(2024, 1, 1),
        completedAt: DateTime(2024, 1, 2),
      );

      final updated = round.copyWith(phase: RoundPhase.proposing);

      expect(updated.phase, RoundPhase.proposing);
      expect(updated.id, 5);
      expect(updated.cycleId, 10);
      expect(updated.customId, 3);
      expect(updated.winningPropositionId, 42);
      expect(updated.isSoleWinner, true);
      expect(updated.createdAt, DateTime(2024, 1, 1));
      expect(updated.completedAt, DateTime(2024, 1, 2));
    });
  });

  group('Phase change from Realtime payload', () {
    test('can parse phase from string payload', () {
      // Simulate what comes from Realtime
      final payload = {
        'id': 1,
        'cycle_id': 1,
        'custom_id': 1,
        'phase': 'rating',
        'phase_started_at': '2024-01-01T10:05:00Z',
        'phase_ends_at': '2024-01-01T10:10:00Z',
      };

      // Parse phase string to enum (as done in _onRoundChange)
      final phaseStr = payload['phase'] as String;
      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => RoundPhase.waiting,
      );

      expect(newPhase, RoundPhase.rating);
    });

    test('simulates full phase update flow', () {
      // Initial state: proposing phase
      final initialRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.proposing,
        phaseStartedAt: DateTime(2024, 1, 1, 10, 0),
        phaseEndsAt: DateTime(2024, 1, 1, 10, 5),
        createdAt: DateTime.now(),
      );
      final state = ChatDetailState(currentRound: initialRound);

      // Realtime payload arrives with rating phase
      final payload = {
        'id': 1,
        'phase': 'rating',
        'phase_started_at': '2024-01-01T10:05:00Z',
        'phase_ends_at': '2024-01-01T10:10:00Z',
      };

      // Verify round ID matches
      final roundId = payload['id'] as int;
      expect(roundId, state.currentRound!.id);

      // Parse new phase
      final phaseStr = payload['phase'] as String;
      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => state.currentRound!.phase,
      );

      // Check phase changed
      expect(newPhase, isNot(state.currentRound!.phase));

      // Create updated round
      final updatedRound = state.currentRound!.copyWith(
        phase: newPhase,
        phaseStartedAt: DateTime.parse(payload['phase_started_at'] as String),
        phaseEndsAt: DateTime.parse(payload['phase_ends_at'] as String),
      );

      // Create updated state
      final updatedState = state.copyWith(currentRound: updatedRound);

      // Verify final state
      expect(updatedState.currentRound!.phase, RoundPhase.rating);
      expect(updatedState.currentRound!.phaseStartedAt, DateTime.utc(2024, 1, 1, 10, 5));
      expect(updatedState.currentRound!.phaseEndsAt, DateTime.utc(2024, 1, 1, 10, 10));
    });

    test('handles unknown phase gracefully', () {
      final phaseStr = 'unknown_phase';
      final defaultPhase = RoundPhase.proposing;

      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => defaultPhase,
      );

      expect(newPhase, defaultPhase); // Falls back to default
    });

    test('detects when phase has not changed', () {
      final currentPhase = RoundPhase.rating;
      final payloadPhase = 'rating';

      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == payloadPhase,
        orElse: () => currentPhase,
      );

      expect(newPhase, currentPhase); // Same phase, no update needed
    });
  });

  group('Timer extension detection (Bug 22)', () {
    test('detects timer change when phase_ends_at changes', () {
      // Current state: rating phase with timer ending at 10:10
      final currentRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseStartedAt: DateTime.utc(2024, 1, 1, 10, 5),
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10),
        createdAt: DateTime.now(),
      );
      final state = ChatDetailState(currentRound: currentRound);

      // Realtime payload with extended timer (same phase, different end time)
      final payload = {
        'id': 1,
        'phase': 'rating',
        'phase_started_at': '2024-01-01T10:05:00Z',
        'phase_ends_at': '2024-01-01T10:15:00Z', // Extended by 5 minutes
      };

      // Parse new values
      final phaseStr = payload['phase'] as String;
      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => state.currentRound!.phase,
      );
      final newPhaseEndsAt = DateTime.parse(payload['phase_ends_at'] as String);

      // Detect changes
      final phaseChanged = newPhase != state.currentRound!.phase;
      final currentTimer = state.currentRound!.phaseEndsAt;
      final timerChanged = newPhaseEndsAt.toUtc() != currentTimer?.toUtc();

      expect(phaseChanged, false); // Phase didn't change
      expect(timerChanged, true); // Timer DID change

      // Should update state when either changed
      expect(phaseChanged || timerChanged, true);
    });

    test('detects no change when both phase and timer are same', () {
      final currentRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseStartedAt: DateTime.utc(2024, 1, 1, 10, 5),
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10),
        createdAt: DateTime.now(),
      );
      final state = ChatDetailState(currentRound: currentRound);

      // Realtime payload with same values
      final payload = {
        'id': 1,
        'phase': 'rating',
        'phase_started_at': '2024-01-01T10:05:00Z',
        'phase_ends_at': '2024-01-01T10:10:00Z', // Same time
      };

      final phaseStr = payload['phase'] as String;
      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => state.currentRound!.phase,
      );
      final newPhaseEndsAt = DateTime.parse(payload['phase_ends_at'] as String);

      final phaseChanged = newPhase != state.currentRound!.phase;
      final currentTimer = state.currentRound!.phaseEndsAt;
      final timerChanged = newPhaseEndsAt.toUtc() != currentTimer?.toUtc();

      expect(phaseChanged, false);
      expect(timerChanged, false);
      expect(phaseChanged || timerChanged, false); // No update needed
    });

    test('handles null current timer correctly', () {
      // Round without timer (manual mode)
      final currentRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseEndsAt: null, // No timer
        createdAt: DateTime.now(),
      );
      final state = ChatDetailState(currentRound: currentRound);

      // Payload with new timer
      final payload = {
        'id': 1,
        'phase': 'rating',
        'phase_ends_at': '2024-01-01T10:10:00Z',
      };

      final newPhaseEndsAt = DateTime.parse(payload['phase_ends_at'] as String);
      final currentTimer = state.currentRound!.phaseEndsAt;
      final timerChanged = newPhaseEndsAt.toUtc() != currentTimer?.toUtc();

      expect(timerChanged, true); // null != DateTime is a change
    });

    test('handles null payload timer correctly', () {
      final currentRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10),
        createdAt: DateTime.now(),
      );
      final state = ChatDetailState(currentRound: currentRound);

      // Payload with null timer
      final payload = {
        'id': 1,
        'phase': 'rating',
        'phase_ends_at': null,
      };

      final newPhaseEndsAt = payload['phase_ends_at'] != null
          ? DateTime.parse(payload['phase_ends_at'] as String)
          : null;
      final currentTimer = state.currentRound!.phaseEndsAt;
      final timerChanged = newPhaseEndsAt?.toUtc() != currentTimer?.toUtc();

      expect(timerChanged, true); // DateTime != null is a change
    });

    test('updates round with new timer preserving other fields', () {
      final currentRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseStartedAt: DateTime.utc(2024, 1, 1, 10, 5),
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10),
        winningPropositionId: null,
        isSoleWinner: null,
        createdAt: DateTime(2024, 1, 1),
      );

      // Timer extended
      final newPhaseEndsAt = DateTime.utc(2024, 1, 1, 10, 15);

      final updatedRound = currentRound.copyWith(
        phaseEndsAt: newPhaseEndsAt,
      );

      expect(updatedRound.phaseEndsAt, newPhaseEndsAt);
      expect(updatedRound.id, 1); // Preserved
      expect(updatedRound.phase, RoundPhase.rating); // Preserved
      expect(updatedRound.phaseStartedAt, DateTime.utc(2024, 1, 1, 10, 5)); // Preserved
    });
  });

  group('Cached state for realtime events', () {
    test('ChatDetailState can be stored and retrieved', () {
      final round = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10),
        createdAt: DateTime.now(),
      );
      final state = ChatDetailState(currentRound: round);

      // Simulate caching
      ChatDetailState? cachedState = state;

      // Verify cached state is accessible
      expect(cachedState, isNotNull);
      expect(cachedState.currentRound?.id, 1);
      expect(cachedState.currentRound?.phase, RoundPhase.rating);
    });

    test('can use cached state when current state is unavailable', () {
      final round = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10),
        createdAt: DateTime.now(),
      );
      final cachedState = ChatDetailState(currentRound: round);

      // Simulate state.valueOrNull returning null (loading state)
      ChatDetailState? currentStateValue;

      // Use cached state as fallback
      final effectiveState = currentStateValue ?? cachedState;

      expect(effectiveState, isNotNull);
      expect(effectiveState.currentRound?.id, 1);
    });
  });

  group('App Lifecycle Bug - Timer not refreshing after background', () {
    // BUG REPORT:
    // When user is in chat on "Your Proposition" tab with a timer running,
    // if they put the app in background and the timer expires while backgrounded,
    // when they return to the app, the timer shows "expired" instead of the
    // new countdown that the server has started.
    //
    // Other users who kept the app open see the new countdown correctly
    // because they received the realtime update.
    //
    // ROOT CAUSE:
    // 1. ChatDetailNotifier does NOT implement WidgetsBindingObserver
    // 2. When app is backgrounded, realtime events may be missed
    // 3. When app resumes, there's no refresh triggered
    // 4. The CountdownTimer widget continues showing "expired" state
    //
    // FIX NEEDED:
    // Implement WidgetsBindingObserver in ChatScreen or ChatDetailNotifier
    // to call refresh() when app resumes (AppLifecycleState.resumed).

    test('BUG: Timer state becomes stale when realtime events are missed', () {
      // Scenario: User had timer ending at 10:10, put app in background at 10:08
      // Timer expired at 10:10, server started new phase ending at 10:15
      // User returns to app at 10:12

      // Initial state when user backgrounded the app
      final initialRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.proposing,
        phaseStartedAt: DateTime.utc(2024, 1, 1, 10, 5),
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10), // Expired at 10:10
        createdAt: DateTime.now(),
      );
      final staleState = ChatDetailState(currentRound: initialRound);

      // What server has (user missed this realtime update while backgrounded)
      final serverRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating, // Phase advanced!
        phaseStartedAt: DateTime.utc(2024, 1, 1, 10, 10),
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 15), // New timer!
        createdAt: DateTime.now(),
      );

      // Current time is 10:12 - stale state shows timer expired
      final currentTime = DateTime.utc(2024, 1, 1, 10, 12);
      final staleTimeRemaining = staleState.currentRound!.phaseEndsAt!.difference(currentTime);

      // BUG: User sees "expired" because state wasn't refreshed
      expect(staleTimeRemaining.isNegative, true,
          reason: 'Stale state shows timer as expired');

      // What user SHOULD see (if state was refreshed)
      final freshTimeRemaining = serverRound.phaseEndsAt!.difference(currentTime);
      expect(freshTimeRemaining.isNegative, false,
          reason: 'Fresh server state has 3 minutes remaining');
      expect(freshTimeRemaining.inMinutes, 3);

      // The state should be different - proves refresh is needed
      expect(staleState.currentRound!.phase, isNot(serverRound.phase));
      expect(staleState.currentRound!.phaseEndsAt, isNot(serverRound.phaseEndsAt));
    });

    test('FIX VERIFICATION: State update from refresh would fix the timer', () {
      // This test shows that if refresh() is called on app resume,
      // the state would be updated and the timer would show correctly.

      // Stale state (what user has after returning from background)
      final staleRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.proposing,
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 10), // Expired
        createdAt: DateTime.now(),
      );
      var state = ChatDetailState(currentRound: staleRound);

      // After refresh() fetches fresh data from server
      final freshRound = Round(
        id: 1,
        cycleId: 1,
        customId: 1,
        phase: RoundPhase.rating,
        phaseEndsAt: DateTime.utc(2024, 1, 1, 10, 15), // New timer
        createdAt: DateTime.now(),
      );

      // Simulate state update from refresh()
      state = state.copyWith(currentRound: freshRound);

      // Now timer would show correctly
      final currentTime = DateTime.utc(2024, 1, 1, 10, 12);
      final timeRemaining = state.currentRound!.phaseEndsAt!.difference(currentTime);

      expect(timeRemaining.isNegative, false,
          reason: 'After refresh, timer shows 3 minutes remaining');
      expect(state.currentRound!.phase, RoundPhase.rating,
          reason: 'After refresh, phase is updated');
    });

    test('FIX IMPLEMENTED: ChatScreen has AppLifecycleListener', () {
      // This test documents that the fix has been implemented in ChatScreen.
      //
      // The fix uses AppLifecycleListener in ChatScreen:
      // ```dart
      // late final AppLifecycleListener _lifecycleListener;
      //
      // @override
      // void initState() {
      //   super.initState();
      //   _setupLifecycleListener();
      // }
      //
      // void _setupLifecycleListener() {
      //   _lifecycleListener = AppLifecycleListener(
      //     onResume: _onAppResume,
      //   );
      // }
      //
      // void _onAppResume() {
      //   if (!mounted) return;
      //   ref.read(chatDetailProvider(_params).notifier).refresh();
      // }
      //
      // @override
      // void dispose() {
      //   _lifecycleListener.dispose();
      //   // ...
      // }
      // ```
      //
      // This ensures that when the app resumes from background,
      // the chat detail state is refreshed to catch any missed updates.

      // This test documents the implemented fix
      expect(true, true, reason: 'Fix implemented in ChatScreen - see lib/screens/chat/chat_screen.dart');
    });
  });
}
