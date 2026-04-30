import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/background_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit tests for the user-level preference side of [BackgroundAudioService].
///
/// The playback side (just_audio) isn't exercised here because it requires a
/// platform channel / real audio engine — enter/leave/setEnabled are all safe
/// no-ops for a non-playing player, and AudioPlayer calls are wrapped in a
/// try/catch that logs via RemoteLog rather than rethrowing, so a
/// non-initialized player can't bubble errors back into callers.
void main() {
  // BackgroundAudioService constructs an AppLifecycleListener, which needs
  // a live WidgetsBinding to register itself.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundAudioService', () {
    late SharedPreferences prefs;
    late BackgroundAudioService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = BackgroundAudioService(prefs);
    });

    tearDown(() async {
      await service.dispose();
    });

    test('defaults to enabled on a fresh install (first-time visitors get music)', () {
      expect(service.isEnabled, isTrue);
    });

    test('setEnabled(false) flips isEnabled and persists the preference', () async {
      await service.setEnabled(false);
      expect(service.isEnabled, isFalse);
      expect(prefs.getBool('background_audio_enabled'), isFalse);
    });

    test('setEnabled(true) persists and subsequent instances read true', () async {
      await service.setEnabled(false);
      await service.setEnabled(true);
      expect(service.isEnabled, isTrue);

      final reload = BackgroundAudioService(prefs);
      addTearDown(reload.dispose);
      expect(reload.isEnabled, isTrue);
    });

    test('pre-seeded OFF preference is respected on construction', () async {
      SharedPreferences.setMockInitialValues({'background_audio_enabled': false});
      final prefs2 = await SharedPreferences.getInstance();
      final service2 = BackgroundAudioService(prefs2);
      addTearDown(service2.dispose);

      expect(service2.isEnabled, isFalse);
    });

    test('leaveChat is safe to call without entering first (idempotent)', () async {
      await service.leaveChat();
      expect(service.isEnabled, isTrue);
    });
  });
}
