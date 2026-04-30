import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/donate_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DonatePromptService', () {
    late SharedPreferences prefs;
    late DonatePromptService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = DonatePromptService(prefs);
    });

    test('canShow is true on a fresh install', () {
      expect(service.canShow(), isTrue);
    });

    test('canShow is false immediately after markShown', () async {
      final now = DateTime(2026, 4, 18, 12, 0, 0);
      await service.markShown(now: now);
      expect(service.canShow(now: now), isFalse);
    });

    test('canShow is still false 1 day later (within 7-day cooldown)',
        () async {
      final shownAt = DateTime(2026, 4, 18, 12, 0, 0);
      await service.markShown(now: shownAt);
      expect(
        service.canShow(now: shownAt.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test('canShow flips back to true after the 7-day cooldown elapses',
        () async {
      final shownAt = DateTime(2026, 4, 18, 12, 0, 0);
      await service.markShown(now: shownAt);
      expect(
        service.canShow(now: shownAt.add(const Duration(days: 7))),
        isTrue,
      );
    });

    test('markEverDonated permanently silences the prompt', () async {
      await service.markEverDonated();
      expect(service.canShow(), isFalse);
      // Even after the cooldown.
      expect(
        service.canShow(now: DateTime.now().add(const Duration(days: 365))),
        isFalse,
      );
    });

    test('state persists across service instances', () async {
      final shownAt = DateTime(2026, 4, 18, 12, 0, 0);
      await service.markShown(now: shownAt);
      final fresh = DonatePromptService(prefs);
      expect(fresh.canShow(now: shownAt), isFalse);
    });
  });
}
