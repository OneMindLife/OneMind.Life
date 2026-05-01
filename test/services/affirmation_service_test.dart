import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/affirmation_service.dart';

void main() {
  group('AffirmationService.failureFromCode', () {
    test('maps each documented sqlstate to the expected typed reason', () {
      // Codes are defined by the affirm_round() RPC in migration
      // 20260430180000_add_affirmations.sql.
      const cases = <String, AffirmationFailure>{
        '42501': AffirmationFailure.notAuthenticated,
        'P0001': AffirmationFailure.notActiveParticipant,
        'P0002': AffirmationFailure.wrongPhase,
        'P0003': AffirmationFailure.notAllowed,
        'P0004': AffirmationFailure.noPreviousWinner,
        'P0005': AffirmationFailure.alreadySubmitted,
        'P0006': AffirmationFailure.alreadySkipped,
        'P0007': AffirmationFailure.alreadyAffirmed,
      };
      for (final entry in cases.entries) {
        expect(AffirmationService.failureFromCode(entry.key), entry.value,
            reason: 'sqlstate ${entry.key} should map to ${entry.value}');
      }
    });

    test('falls back to unknown for unrecognized or null codes', () {
      expect(
          AffirmationService.failureFromCode('99999'), AffirmationFailure.unknown);
      expect(AffirmationService.failureFromCode(null), AffirmationFailure.unknown);
      expect(AffirmationService.failureFromCode(''), AffirmationFailure.unknown);
    });
  });

  group('AffirmationException', () {
    test('toString includes the failure name and message', () {
      final exception = AffirmationException(
        AffirmationFailure.alreadySubmitted,
        'already submitted a proposition, cannot affirm',
      );
      expect(
        exception.toString(),
        'AffirmationException(alreadySubmitted): '
        'already submitted a proposition, cannot affirm',
      );
    });

    test('exposes its reason and message fields', () {
      final exception = AffirmationException(
        AffirmationFailure.noPreviousWinner,
        'no previous winner to affirm',
      );
      expect(exception.reason, AffirmationFailure.noPreviousWinner);
      expect(exception.message, 'no previous winner to affirm');
    });
  });
}
