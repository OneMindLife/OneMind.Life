import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/chat/chat_screen.dart';

/// Tapping the round-winner card: quick chats (maxCycles==1) and instant chats
/// (confirmationRounds==1) jump to the round's FULL rankings; full-wizard
/// multi-cycle convergence chats open the cycle-history (round-winners) list.
/// Regression guard for the 2026-06-06 fix where the convergence on-ramp
/// (confirmationRounds=2) silently rerouted quick-chat taps to cycle history.
void main() {
  group('winnerTapShowsRoundResults', () {
    test('instant chat (confirmationRounds==1) → full round results', () {
      expect(
        winnerTapShowsRoundResults(confirmationRounds: 1, maxCycles: null),
        isTrue,
      );
    });

    test('quick chat, instant (rounds==1, maxCycles==1) → full results', () {
      expect(
        winnerTapShowsRoundResults(confirmationRounds: 1, maxCycles: 1),
        isTrue,
      );
    });

    test('quick CONVERGENCE chat (rounds==2, maxCycles==1) → full results '
        '(the fix: not cycle history)', () {
      expect(
        winnerTapShowsRoundResults(confirmationRounds: 2, maxCycles: 1),
        isTrue,
      );
    });

    test('full-wizard convergence (rounds==2, maxCycles==null) → cycle history',
        () {
      expect(
        winnerTapShowsRoundResults(confirmationRounds: 2, maxCycles: null),
        isFalse,
      );
    });

    test('full-wizard multi-cycle (rounds==3, maxCycles==5) → cycle history',
        () {
      expect(
        winnerTapShowsRoundResults(confirmationRounds: 3, maxCycles: 5),
        isFalse,
      );
    });
  });
}
