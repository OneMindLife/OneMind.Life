import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/config/router.dart';

/// The marketing landing ('/') is a web-only surface. These tests pin the
/// exact platform matrix so the WEB behavior can never regress when the native
/// behavior changes (App Store review flagged the native app opening to the
/// "Try It Free" hero — Guideline 2.3.3 — so native must skip it).
void main() {
  group('shouldSkipLandingForApp', () {
    group('native app (isWeb == false)', () {
      test('ALWAYS skips the landing -> straight into the app', () {
        expect(
          shouldSkipLandingForApp(
            isLandingRoute: true,
            isWeb: false,
            isStandalonePwa: false,
          ),
          isTrue,
        );
      });

      test('skips regardless of the (irrelevant) PWA flag', () {
        expect(
          shouldSkipLandingForApp(
            isLandingRoute: true,
            isWeb: false,
            isStandalonePwa: true,
          ),
          isTrue,
        );
      });

      test('never fires for a non-landing route', () {
        expect(
          shouldSkipLandingForApp(
            isLandingRoute: false,
            isWeb: false,
            isStandalonePwa: false,
          ),
          isFalse,
        );
      });
    });

    group('web (isWeb == true) — behavior must be UNCHANGED', () {
      test('new web visitor (not installed) SEES the landing', () {
        expect(
          shouldSkipLandingForApp(
            isLandingRoute: true,
            isWeb: true,
            isStandalonePwa: false,
          ),
          isFalse,
        );
      });

      test('installed PWA user SKIPS the landing (existing behavior)', () {
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
  });
}
