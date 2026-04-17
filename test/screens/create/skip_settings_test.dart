import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';

void main() {
  group('SkipSettings', () {
    test('defaults to allowing both skips', () {
      final settings = SkipSettings.defaults();

      expect(settings.allowSkipProposing, true);
      expect(settings.allowSkipRating, true);
    });

    test('copyWith updates allowSkipProposing', () {
      final settings = SkipSettings.defaults();
      final updated = settings.copyWith(allowSkipProposing: false);

      expect(updated.allowSkipProposing, false);
      expect(updated.allowSkipRating, true);
    });

    test('copyWith updates allowSkipRating', () {
      final settings = SkipSettings.defaults();
      final updated = settings.copyWith(allowSkipRating: false);

      expect(updated.allowSkipProposing, true);
      expect(updated.allowSkipRating, false);
    });

    test('equality works correctly', () {
      const a = SkipSettings(allowSkipProposing: true, allowSkipRating: true);
      const b = SkipSettings(allowSkipProposing: true, allowSkipRating: true);
      const c = SkipSettings(allowSkipProposing: false, allowSkipRating: true);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
