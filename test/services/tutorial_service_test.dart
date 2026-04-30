import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/tutorial_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TutorialService', () {
    late SharedPreferences prefs;
    late TutorialService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = TutorialService(prefs);
    });

    test('hasAutoJoinedOfficial defaults to false', () {
      expect(service.hasAutoJoinedOfficial, isFalse);
    });

    test('markOfficialAutoJoined flips the flag and persists', () async {
      await service.markOfficialAutoJoined();
      expect(service.hasAutoJoinedOfficial, isTrue);

      // A fresh service reading the same prefs sees the persisted value.
      final fresh = TutorialService(prefs);
      expect(fresh.hasAutoJoinedOfficial, isTrue);
    });

    test('flag is independent of tutorial / home tour flags', () async {
      await service.markOfficialAutoJoined();
      expect(service.hasCompletedTutorial, isFalse);
      expect(service.hasCompletedHomeTour, isFalse);
    });
  });
}
