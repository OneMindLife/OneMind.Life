import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/error_view.dart';
import '../screens/discover/discover_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/join/invite_join_screen.dart';
import '../screens/legal/legal_document_screen.dart';
import '../screens/demo/demo_screen.dart';
import '../screens/home_tour/home_tour_screen.dart';
import '../screens/tutorial/tutorial_screen.dart';
import '../utils/seo/seo_meta.dart';

/// Global navigator key for accessing navigator from anywhere
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Guard to prevent double-execution of tutorial completion
bool _tutorialCompletionInProgress = false;

/// App router configuration
final routerProvider = Provider<GoRouter>((ref) {
  final analyticsService = ref.watch(analyticsServiceProvider);
  final observer = analyticsService.observer;
  final hasCompletedTutorial = ref.watch(hasCompletedTutorialProvider);
  final hasCompletedHomeTour = ref.watch(hasCompletedHomeTourProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    observers: observer != null ? [observer] : [],
    // Redirect first-time users to tutorial, then home tour
    redirect: (context, state) {
      updateMetaTags(state.matchedLocation);
      final isGoingToTutorial = state.matchedLocation == '/tutorial';
      final isHomeTourRoute = state.matchedLocation == '/home-tour';
      final isJoinRoute = state.matchedLocation.startsWith('/join');
      final isLegalRoute = state.matchedLocation == '/privacy' ||
          state.matchedLocation == '/terms';
      final isDemoRoute = state.matchedLocation == '/demo';
      final isDiscoverRoute = state.matchedLocation == '/discover';

      if (kDebugMode) {
        debugPrint('[Router] redirect: path=${state.matchedLocation} '
            'tutorial=$hasCompletedTutorial homeTour=$hasCompletedHomeTour');
      }

      // Don't redirect if already going to tutorial
      if (isGoingToTutorial) return null;

      // Don't redirect join routes (user is joining via invite link)
      if (isJoinRoute) return null;

      // Don't redirect legal routes (accessible from tutorial)
      if (isLegalRoute) return null;

      // Don't redirect demo route (accessible without tutorial)
      if (isDemoRoute) return null;

      // Don't redirect discover route (accessible from home app bar)
      if (isDiscoverRoute) return null;

      // Home tour route: redirect to home if already completed
      if (isHomeTourRoute && hasCompletedHomeTour) {
        if (kDebugMode) {
          debugPrint('[Router] home tour already completed, redirecting to /');
        }
        return '/';
      }
      if (isHomeTourRoute) return null;

      // Redirect to tutorial if not completed
      if (!hasCompletedTutorial) {
        return '/tutorial';
      }

      // First-time user completed tutorial but not home tour → show tour
      if (!hasCompletedHomeTour) {
        if (kDebugMode) {
          debugPrint('[Router] tutorial done but home tour not done, '
              'redirecting to /home-tour');
        }
        return '/home-tour';
      }

      return null;
    },
    routes: [
      // Tutorial route
      GoRoute(
        path: '/tutorial',
        name: 'tutorial',
        builder: (context, state) => TutorialScreen(
          onSkip: () {
            // Skip tutorial AND home tour — go straight to the real app
            ref.read(tutorialServiceProvider).markTutorialComplete();
            ref.read(tutorialServiceProvider).markHomeTourComplete();
            ref.invalidate(hasCompletedTutorialProvider);
            ref.invalidate(hasCompletedHomeTourProvider);
          },
          onComplete: () async {
            // Prevent double-execution (can happen when router rebuilds)
            if (_tutorialCompletionInProgress) {
              return;
            }
            _tutorialCompletionInProgress = true;

            try {
              // Check if this is a returning user (already completed tutorial,
              // opened it from "How It Works" button)
              final isFirstTime = !ref.read(hasCompletedTutorialProvider);

              if (kDebugMode) {
                debugPrint('[Router] tutorial onComplete: '
                    'isFirstTime=$isFirstTime');
              }

              // Mark tutorial as complete FIRST so user is never stuck
              // on a broken tutorial screen if network calls fail
              ref.read(tutorialServiceProvider).markTutorialComplete();

              if (!isFirstTime) {
                // Returning user ("How It Works") — reset home tour
                // so they get the full onboarding experience again
                await ref.read(tutorialServiceProvider).resetHomeTour();
                ref.invalidate(hasCompletedTutorialProvider);
                ref.invalidate(hasCompletedHomeTourProvider);
                // Router redirect will see hasCompletedHomeTour=false
                // and send to /home-tour
                return;
              }

              // First-time user: auto-join official chat silently
              try {
                final chatService = ref.read(chatServiceProvider);
                final participantService = ref.read(participantServiceProvider);
                final officialChat = await chatService.getOfficialChat();
                if (officialChat != null) {
                  await participantService.joinPublicChat(
                      chatId: officialChat.id);
                  if (kDebugMode) {
                    debugPrint('[Router] auto-joined official chat');
                  }
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[Router] failed to join official chat: $e');
                }
              }

              // Invalidate AFTER join attempt so redirect fires with
              // hasCompletedTutorial=true + hasCompletedHomeTour=false
              // → router redirects to /home-tour automatically
              if (kDebugMode) {
                debugPrint('[Router] invalidating tutorial provider, '
                    'expecting redirect to /home-tour');
              }
              ref.invalidate(hasCompletedTutorialProvider);
            } finally {
              _tutorialCompletionInProgress = false;
            }
          },
        ),
      ),
      // Home tour route (shown after tutorial for first-time users)
      GoRoute(
        path: '/home-tour',
        name: 'home-tour',
        builder: (context, state) => HomeTourScreen(
          onComplete: () {
            if (kDebugMode) {
              debugPrint('[Router] home tour onComplete — marking done, '
                  'expecting redirect to /');
            }
            ref.read(tutorialServiceProvider).markHomeTourComplete();
            // Invalidating triggers router rebuild; redirect sees
            // hasCompletedHomeTour=true and sends /home-tour → /
            ref.invalidate(hasCompletedHomeTourProvider);
          },
        ),
      ),
      // Home route
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) {
          // Support ?chat_id=X for returning from Stripe checkout
          final chatIdParam = state.uri.queryParameters['chat_id'];
          final returnToChatId = chatIdParam != null ? int.tryParse(chatIdParam) : null;
          return HomeScreen(returnToChatId: returnToChatId);
        },
      ),
      // Discover route
      GoRoute(
        path: '/discover',
        name: 'discover',
        builder: (context, state) => const DiscoverScreen(),
      ),
      // Demo route
      GoRoute(
        path: '/demo',
        name: 'demo',
        builder: (context, state) => const DemoScreen(),
      ),
      // Legal routes
      GoRoute(
        path: '/privacy',
        name: 'privacy',
        builder: (context, state) => const LegalDocumentScreen.privacyPolicy(),
      ),
      GoRoute(
        path: '/terms',
        name: 'terms',
        builder: (context, state) => const LegalDocumentScreen.termsOfService(),
      ),
      // Invite token route: /join/invite?token=xxx
      GoRoute(
        path: '/join/invite',
        name: 'join-invite',
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          return InviteJoinScreen(token: token);
        },
      ),
      // Invite code route: /join/:code (for backwards compatibility)
      GoRoute(
        path: '/join/:code',
        name: 'join-code',
        redirect: (context, state) {
          final code = state.pathParameters['code']?.toUpperCase();
          // Tutorial code redirects to tutorial
          if (code == 'ABC123') {
            return '/tutorial';
          }
          return null;
        },
        builder: (context, state) {
          final code = state.pathParameters['code'];
          return InviteJoinScreen(code: code);
        },
      ),
    ],
    errorBuilder: (context, state) {
      setNoIndex();
      final l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.pageNotFound)),
        body: ErrorView(
          message: l10n.pageNotFoundMessage,
          details: state.uri.toString(),
          onRetry: () => context.go('/'),
          actionLabel: l10n.goHome,
          actionIcon: Icons.home,
        ),
      );
    },
  );
});
