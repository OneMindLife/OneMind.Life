import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/config/router.dart';

/// The marketing landing ('/') now lives on the WEDGE (onemind.life). This
/// Flutter app is purely the app surface (app.onemind.life), so '/' always
/// redirects into /home on every platform (native, web, and installed PWA).
void main() {
  group('shouldSkipLandingForApp', () {
    test('always skips the landing route -> straight into /home', () {
      // Native
      expect(
        shouldSkipLandingForApp(
          isLandingRoute: true,
          isWeb: false,
          isStandalonePwa: false,
        ),
        isTrue,
      );
      // Web (new visitor)
      expect(
        shouldSkipLandingForApp(
          isLandingRoute: true,
          isWeb: true,
          isStandalonePwa: false,
        ),
        isTrue,
      );
      // Web (installed PWA)
      expect(
        shouldSkipLandingForApp(
          isLandingRoute: true,
          isWeb: true,
          isStandalonePwa: true,
        ),
        isTrue,
      );
    });

    test('never fires for a non-landing route', () {
      expect(
        shouldSkipLandingForApp(
          isLandingRoute: false,
          isWeb: true,
          isStandalonePwa: true,
        ),
        isFalse,
      );
    });
  });
}
