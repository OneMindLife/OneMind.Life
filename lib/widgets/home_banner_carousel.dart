import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';
import '../utils/pwa_install.dart';

/// Banner carousel shown above the home search bar. Rotates between
/// "Install OneMind" and "Enable notifications" slides depending on what
/// the current environment supports and what the user hasn't dismissed.
///
/// - 0 eligible slides → nothing renders.
/// - 1 eligible slide → static card, no arrows, no auto-cycle.
/// - 2 eligible slides → fade crossfade every 6s, arrows on either side.
///   Tapping an arrow resets the 6s auto-timer so manual interaction never
///   collides with a background tick.
class HomeBannerCarousel extends ConsumerStatefulWidget {
  const HomeBannerCarousel({super.key});

  @override
  ConsumerState<HomeBannerCarousel> createState() =>
      _HomeBannerCarouselState();
}

/// Slide kinds the carousel can surface. Public so tests can assert which
/// slides were selected by [computeHomeBannerSlides].
enum HomeBannerSlide { install, notifications }

/// Pure decision function that produces the list of eligible slides from
/// the current environment. Extracted so it can be unit-tested without
/// pulling in Firebase / PageView / a live widget tree.
///
/// Rules:
/// - Install slide appears on **mobile web** when the app isn't already
///   running as an installed PWA. Desktop (`isMobile=false`) never sees it.
/// - Notifications slide appears on **web** when permission is
///   [AuthorizationStatus.notDetermined] and the user hasn't dismissed
///   the prompt. iOS outside of an installed PWA can't request web push,
///   so it's suppressed there (Apple restriction).
List<HomeBannerSlide> computeHomeBannerSlides({
  required bool isWeb,
  required bool isMobile,
  required bool isPwaInstalled,
  required bool isIos,
  required bool pushDismissed,
  required AuthorizationStatus? pushStatus,
}) {
  final slides = <HomeBannerSlide>[];

  if (isWeb && isMobile && !isPwaInstalled) {
    slides.add(HomeBannerSlide.install);
  }

  // The notifications slide appears whenever the user hasn't enabled push
  // and hasn't dismissed the banner. Two rendered variants:
  //   * notDetermined → prompt + "Enable" button.
  //   * denied → info card guiding the user to unblock in site settings
  //              (browsers won't let us re-prompt once denied).
  final notifEligible = isWeb && !(isIos && !isPwaInstalled);
  final needsPrompt = pushStatus == AuthorizationStatus.notDetermined ||
      pushStatus == AuthorizationStatus.denied;
  if (notifEligible && !pushDismissed && needsPrompt) {
    slides.add(HomeBannerSlide.notifications);
  }

  return slides;
}

class _HomeBannerCarouselState extends ConsumerState<HomeBannerCarousel> {
  static const _autoAdvance = Duration(seconds: 6);
  // Longer duration + strong ease-out curve gives a gliding arrival
  // instead of an abrupt stop when the card is almost fully on-screen.
  static const _slideAnim = Duration(milliseconds: 900);
  static const _slideCurve = Curves.easeOutQuart;

  bool _loading = true;
  List<HomeBannerSlide> _slides = [];
  int _index = 0;
  Timer? _autoTimer;
  bool _busy = false;
  AuthorizationStatus? _pushStatus;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _determineSlides();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _determineSlides() async {
    final kIsWebFlag = kIsWeb;
    final mobile = kIsWebFlag ? isMobileDevice() : false;
    final installed = kIsWebFlag ? isPwaInstalled() : false;
    final ios = kIsWebFlag ? isIos() : false;

    final tutorialService = ref.read(tutorialServiceProvider);
    final pushDismissed = tutorialService.hasDismissedPushPrompt;

    // iOS outside of a PWA can't surface the permission prompt, so don't
    // even call into the service there (it would throw on some browsers).
    final notifEligible = kIsWebFlag && !(ios && !installed);
    AuthorizationStatus? pushStatus;
    if (notifEligible && !pushDismissed) {
      try {
        pushStatus = await ref
            .read(pushNotificationServiceProvider)
            .getPermissionStatus();
      } catch (_) {
        // Permission lookup failed — treat as unknown and skip the slide.
      }
    }

    final slides = computeHomeBannerSlides(
      isWeb: kIsWebFlag,
      isMobile: mobile,
      isPwaInstalled: installed,
      isIos: ios,
      pushDismissed: pushDismissed,
      pushStatus: pushStatus,
    );

    if (!mounted) return;
    setState(() {
      _slides = slides;
      _pushStatus = pushStatus;
      _loading = false;
    });
    _restartAutoTimer();
  }

  void _restartAutoTimer() {
    _autoTimer?.cancel();
    if (_slides.length < 2) return;
    _autoTimer = Timer.periodic(_autoAdvance, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_index + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: _slideAnim,
        curve: _slideCurve,
      );
    });
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    // Reset the auto-timer on any change so manual swipes give the user
    // a full 6s before the next auto-advance.
    _restartAutoTimer();
  }

  void _removeSlide(HomeBannerSlide slide) {
    setState(() {
      _slides = List.of(_slides)..remove(slide);
      if (_slides.isEmpty) {
        _autoTimer?.cancel();
      } else if (_index >= _slides.length) {
        _index = 0;
      }
    });
    if (_pageController.hasClients && _slides.isNotEmpty) {
      _pageController.jumpToPage(_index);
    }
    _restartAutoTimer();
  }

  Future<void> _onInstall() async {
    if (_busy) return;
    setState(() => _busy = true);
    final accepted = await triggerPwaInstall();
    if (!mounted) return;
    setState(() => _busy = false);
    if (accepted) _removeSlide(HomeBannerSlide.install);
  }

  Future<void> _onEnableNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    final pushService = ref.read(pushNotificationServiceProvider);
    try {
      // Ask the user. This may throw later (FCM token fetch) even after
      // permission was granted — we swallow the error and rely on the
      // actual permission status below, not the call's success.
      await pushService.requestAndRegister();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);

    // Re-read the browser's authoritative permission state so the UI
    // always reflects what the user actually chose.
    final status = await pushService.getPermissionStatus();
    if (!mounted) return;

    if (status == AuthorizationStatus.authorized) {
      // Enabled — retire the slide (browser won't re-prompt) and persist.
      await ref.read(tutorialServiceProvider).markPushPromptDismissed();
      if (mounted) _removeSlide(HomeBannerSlide.notifications);
    } else if (status == AuthorizationStatus.denied) {
      // Swap to the "blocked" variant so the user keeps seeing guidance
      // about unblocking via site settings. They can then tap Got it to
      // retire the slide whenever they're done reading.
      setState(() => _pushStatus = status);
    }
    // If still notDetermined (prompt closed without a choice), leave the
    // slide in place so they can tap again.
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _slides.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final multi = _slides.length > 1;

    // Single slide — render as a plain card (no PageView, no dots).
    if (!multi) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _slideCard(_slides[_index], theme),
      );
    }

    // Carousel — full-width swipeable PageView with a dot indicator
    // overlaid on top of each card. Outer horizontal padding is 8px (half
    // of the search field's 16px gutter); each PageView page adds the
    // other 8px internally. Net: cards sit 16px from the screen edge
    // (aligned with the search field) while leaving a 16px gap between
    // neighboring cards during a swipe.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SizedBox(
        height: _carouselHeight(theme),
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              // Inset each page so neighboring cards aren't edge-to-edge
              // while sliding. 8px per side → 16px visible gap between
              // adjacent cards mid-transition.
              children: _slides
                  .map((s) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _slideCard(s, theme),
                      ))
                  .toList(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: _DotIndicator(
                count: _slides.length,
                active: _index,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Carousel needs a bounded height since PageView is unbounded by default.
  /// Both cards are roughly the same height (icon + 2 lines + CTA); measure
  /// once with the current theme's text style to stay locale/size aware.
  double _carouselHeight(ThemeData theme) {
    // Small overhead for the dot indicator that sits at the bottom.
    return 84;
  }

  Widget _slideCard(HomeBannerSlide slide, ThemeData theme) {
    switch (slide) {
      case HomeBannerSlide.install:
        return _installCard(theme);
      case HomeBannerSlide.notifications:
        return _notifCard(theme);
    }
  }

  Widget _installCard(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;
    final ios = isIos();
    return Material(
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              ios ? Icons.ios_share : Icons.install_mobile,
              color: onContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.installOneMindTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: onContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ios
                        ? l10n.installOneMindIosBody
                        : l10n.installOneMindBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            if (!ios)
              TextButton(
                key: const Key('install-pwa-button'),
                onPressed: _busy ? null : _onInstall,
                style: TextButton.styleFrom(foregroundColor: onContainer),
                child: Text(l10n.installCta),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notifCard(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    // `denied` means the browser remembers a prior "Block" decision and
    // won't surface the native permission prompt again. Swap the card
    // into an informational variant pointing the user at site settings.
    final isBlocked = _pushStatus == AuthorizationStatus.denied;
    final title = isBlocked
        ? l10n.notificationsBlockedTitle
        : l10n.enableNotificationsTitle;
    final body = isBlocked
        ? l10n.notificationsBlockedBody
        : l10n.enableNotificationsBody;
    final icon = isBlocked
        ? Icons.notifications_off_outlined
        : Icons.notifications_active_outlined;

    return Material(
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: onContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: onContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            if (isBlocked)
              TextButton(
                key: const Key('notifications-blocked-got-it-button'),
                onPressed: _busy ? null : _onBlockedAck,
                style: TextButton.styleFrom(foregroundColor: onContainer),
                child: Text(l10n.gotIt),
              )
            else
              TextButton(
                key: const Key('enable-notifications-button'),
                onPressed: _busy ? null : _onEnableNotifications,
                style: TextButton.styleFrom(foregroundColor: onContainer),
                child: Text(l10n.enableNotificationsCta),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onBlockedAck() async {
    await ref.read(tutorialServiceProvider).markPushPromptDismissed();
    if (!mounted) return;
    _removeSlide(HomeBannerSlide.notifications);
  }
}

/// Small horizontal row of dots indicating the active slide. The active dot
/// stretches into a pill and brightens; inactive dots dim.
class _DotIndicator extends StatelessWidget {
  final int count;
  final int active;
  final Color color;

  const _DotIndicator({
    required this.count,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: isActive ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isActive ? 1.0 : 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
