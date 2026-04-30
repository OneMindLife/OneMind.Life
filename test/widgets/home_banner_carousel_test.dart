import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/home_banner_carousel.dart';

/// Unit tests for the pure decision function behind [HomeBannerCarousel].
/// The widget itself can't be exercised on the Dart VM because its logic
/// depends on compile-time `kIsWeb` plus platform channels, so we cover
/// behavior through this extracted function.
void main() {
  group('computeHomeBannerSlides', () {
    group('non-web platform', () {
      test('returns no slides (no banners on native)', () {
        final slides = computeHomeBannerSlides(
          isWeb: false,
          isMobile: true,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, isEmpty);
      });
    });

    group('desktop web', () {
      test('desktop + browser + pending push → notifications only', () {
        // Desktop = isMobile false, so install is skipped. Notifications
        // can still be offered because desktop web supports push.
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: false,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, [HomeBannerSlide.notifications]);
      });

      test('desktop + permission already granted → no slides', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: false,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.authorized,
        );
        expect(slides, isEmpty);
      });

      test(
          'desktop + permission denied → notifications slide '
          '(blocked-variant guidance)', () {
        // Denied users still see the notif slide; the widget renders it
        // as the "blocked" variant pointing at site settings, since the
        // browser won't let us re-prompt.
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: false,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.denied,
        );
        expect(slides, [HomeBannerSlide.notifications]);
      });

      test('desktop + denied + user dismissed → no slides', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: false,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: true,
          pushStatus: AuthorizationStatus.denied,
        );
        expect(slides, isEmpty);
      });

      test('desktop + user dismissed prompt → no slides', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: false,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: true,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, isEmpty);
      });
    });

    group('denied status surfaces blocked-variant slide', () {
      test('Android browser + denied + not installed → install + notif',
          () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.denied,
        );
        expect(slides, [
          HomeBannerSlide.install,
          HomeBannerSlide.notifications,
        ]);
      });

      test('iOS PWA + denied → notifications (blocked variant)', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: true,
          isIos: true,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.denied,
        );
        expect(slides, [HomeBannerSlide.notifications]);
      });

      test('iOS browser + denied → install only '
          '(notif still suppressed on iOS non-PWA)', () {
        // iOS Safari forbids web push entirely outside of a PWA; the
        // denied status shouldn't override that restriction.
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: true,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.denied,
        );
        expect(slides, [HomeBannerSlide.install]);
      });

      test('denied + user already acknowledged → no slide', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: true,
          pushStatus: AuthorizationStatus.denied,
        );
        expect(slides, [HomeBannerSlide.install]);
      });
    });

    group('Android browser', () {
      test(
          'mobile + not installed + pending push → install and notifications (carousel)',
          () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, [
          HomeBannerSlide.install,
          HomeBannerSlide.notifications,
        ]);
      });

      test(
          'mobile + not installed + permission authorized → install only',
          () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.authorized,
        );
        expect(slides, [HomeBannerSlide.install]);
      });

      test('mobile + already installed → notifications only (no install)',
          () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: true,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, [HomeBannerSlide.notifications]);
      });
    });

    group('iOS browser (Apple-restricted web push)', () {
      test(
          'iOS + browser + not installed → install only '
          '(notif not allowed until PWA)', () {
        // iOS Safari refuses web push in a regular tab. Only the install
        // nudge is appropriate; the notif slide is suppressed regardless of
        // permission status.
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: true,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, [HomeBannerSlide.install]);
      });

      test(
          'iOS + PWA installed + pending push → notifications only '
          '(install already done)', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: true,
          isIos: true,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides, [HomeBannerSlide.notifications]);
      });

      test('iOS + PWA installed + permission granted → nothing', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: true,
          isIos: true,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.authorized,
        );
        expect(slides, isEmpty);
      });
    });

    group('edge cases', () {
      test('null pushStatus is treated as not-notDetermined (no slide)', () {
        // getPermissionStatus returning null means the lookup didn't run
        // (e.g. non-web or the call was short-circuited).
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: false,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: null,
        );
        expect(slides, isEmpty);
      });

      test('slide order is stable: install first, notifications second', () {
        final slides = computeHomeBannerSlides(
          isWeb: true,
          isMobile: true,
          isPwaInstalled: false,
          isIos: false,
          pushDismissed: false,
          pushStatus: AuthorizationStatus.notDetermined,
        );
        expect(slides.first, HomeBannerSlide.install);
        expect(slides.last, HomeBannerSlide.notifications);
      });
    });
  });
}
