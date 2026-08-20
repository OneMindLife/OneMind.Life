import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'quick_chat_guard.dart';
import 'route_transition_logger.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/error_view.dart';
import '../screens/discover/discover_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/blog/blog_data.dart';
import '../screens/blog/blog_index_screen.dart';
import '../screens/blog/blog_post_screen.dart';
import '../screens/landing/landing_screen.dart';
import '../screens/landing/seo_landing_page.dart';
import '../screens/landing/seo_pages.dart';
import '../screens/join/invite_join_screen.dart';
import '../screens/legal/legal_document_screen.dart';
import '../screens/action_picker/action_picker_screen.dart';
import '../screens/demo/demo_screen.dart';
import '../screens/demo/demo_vote_screen.dart';
import '../screens/home_tour/home_tour_screen.dart';
import '../screens/tutorial/tutorial_screen.dart';
import '../utils/pwa_detector.dart';
import '../utils/seo/seo_meta.dart';

/// Global navigator key for accessing navigator from anywhere
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Guard to prevent double-execution of tutorial completion
bool _tutorialCompletionInProgress = false;

/// Whether a request for the marketing landing (`/`) should be redirected
/// straight into the app (`/home`) instead of showing the hero.
///
/// The landing is a WEB-ONLY acquisition surface (SEO + new-visitor funnel):
///  * **Native app** (`isWeb == false`): always skip it. A user who installed
///    the app already converted, and opening a native app to a "Try It Free"
///    hero confused App Store review — the first screen matched no screenshot,
///    causing repeated Guideline 2.3.3 rejections.
///  * **Web** (`isWeb == true`): unchanged — installed PWA users skip it (this
///    also catches the old PWA manifest's `start_url="."` → `/`), while new web
///    visitors still see the marketing landing.
///
/// Pure (no platform calls) so every branch is unit-testable.
bool shouldSkipLandingForApp({
  required bool isLandingRoute,
  required bool isWeb,
  required bool isStandalonePwa,
}) =>
    isLandingRoute && (!isWeb || isStandalonePwa);

/// App router configuration
final routerProvider = Provider<GoRouter>((ref) {
  final analyticsService = ref.watch(analyticsServiceProvider);
  final observer = analyticsService.observer;
  final hasCompletedHomeTour = ref.watch(hasCompletedHomeTourProvider);

  late final GoRouter router;
  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    observers: [
      if (observer != null) observer,
      // TEMPORARY (2026-06-07): remote-logs route transitions to client_logs to
      // diagnose the "stranded on a marketing page after browser-back" trap.
      // Remove once understood + fixed.
      RouteTransitionLogger(),
    ],
    // Redirect first-time users to tutorial, then home tour
    redirect: (context, state) {
      updateMetaTags(state.matchedLocation);

      // D37 sealed-loop guard (interim, until the quick-chat wedge moves to
      // Next.js): once a host is inside their created quick chat, OS/browser
      // back must not strand them on the marketing funnel. go_router keeps every
      // nav in browser history (proven — no primitive avoids it), so we
      // intercept here: any navigation to a funnel route while a quick chat is
      // active bounces back to that chat. The forward exit is the chat's
      // "Create a new chat" button, which clears the guard first.
      final guardTarget = quickChatGuardRedirect(
        state.matchedLocation,
        activeQuickChatId.value,
        seoPages.containsKey,
      );
      if (guardTarget != null) return guardTarget;

      final isLandingRoute = state.matchedLocation == '/';
      final isHomeRoute = state.matchedLocation == '/home';
      final isGoingToTutorial = state.matchedLocation == '/tutorial';
      final isHomeTourRoute = state.matchedLocation == '/home-tour';
      final isJoinRoute = state.matchedLocation.startsWith('/join');
      final isLegalRoute = state.matchedLocation == '/privacy' ||
          state.matchedLocation == '/terms';
      final isDemoRoute = state.matchedLocation == '/demo' ||
          state.matchedLocation == '/try';
      final isDiscoverRoute = state.matchedLocation == '/discover';

      // The marketing landing ('/') is a WEB-ONLY acquisition surface (SEO +
      // new-visitor funnel). See [shouldSkipLandingForApp]: native builds
      // always open straight into the app; web keeps its existing behavior.
      if (shouldSkipLandingForApp(
        isLandingRoute: isLandingRoute,
        isWeb: kIsWeb,
        isStandalonePwa: isStandalonePwa(),
      )) {
        return '/home';
      }

      // Don't redirect landing page (accessible to new users)
      if (isLandingRoute) return null;

      // Don't redirect home route (where app logic happens)
      if (isHomeRoute) return null;

      // Don't redirect if already going to tutorial
      if (isGoingToTutorial) return null;

      // Don't redirect join routes (user is joining via invite link)
      if (isJoinRoute) return null;

      // Don't redirect legal routes (accessible from tutorial)
      if (isLegalRoute) return null;

      // Don't redirect demo route (accessible without tutorial)
      if (isDemoRoute) return null;

      // Don't redirect SEO landing pages (accessible without tutorial)
      final isSeoRoute = seoPages.containsKey(
          state.matchedLocation.replaceFirst('/', ''));
      if (isSeoRoute) return null;

      // Don't redirect blog routes (accessible without tutorial)
      if (state.matchedLocation.startsWith('/blog')) return null;

      // Don't redirect discover route (accessible from home app bar)
      if (isDiscoverRoute) return null;

      // Home tour route: redirect to home if already completed
      if (isHomeTourRoute && hasCompletedHomeTour) {
        return '/home';
      }
      if (isHomeTourRoute) return null;

      return null;
    },
    routes: [
      // Tutorial route
      GoRoute(
        path: '/tutorial',
        name: 'tutorial',
        builder: (context, state) => TutorialScreen(
          skipIntro: state.uri.queryParameters['skipIntro'] == 'true',
          onSkip: () {
            // Skip tutorial AND home tour — go straight to the real app
            ref.read(tutorialServiceProvider).markTutorialComplete();
            ref.read(tutorialServiceProvider).markHomeTourComplete();
            ref.invalidate(hasCompletedTutorialProvider);
            ref.invalidate(hasCompletedHomeTourProvider);
          },
          onComplete: () async {
            // Prevent double-execution (can happen when router rebuilds)
            if (_tutorialCompletionInProgress) return;
            _tutorialCompletionInProgress = true;

            try {
              final isFirstTime = !ref.read(hasCompletedTutorialProvider);

              ref.read(tutorialServiceProvider).markTutorialComplete();

              if (!isFirstTime) {
                // Returning user ("How It Works") — reset home tour
                // so they get the full onboarding experience again
                await ref.read(tutorialServiceProvider).resetHomeTour();
              }

              // Auto-join into the official chat now happens on first
              // visit to the Home screen (see _ensureJoinedOfficialChat
              // in home_screen.dart) so users who later leave are not
              // forcibly re-added on every tutorial revisit.

              // Invalidate providers so the router rebuilds with fresh
              // values (homeTour=false), then navigate on the next frame
              // so the new router instance handles the /home-tour route.
              ref.invalidate(hasCompletedTutorialProvider);
              ref.invalidate(hasCompletedHomeTourProvider);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                router.go('/home-tour');
              });
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
            ref.read(tutorialServiceProvider).markHomeTourComplete();
            // Invalidating triggers router rebuild; redirect sees
            // hasCompletedHomeTour=true and sends /home-tour → /
            ref.invalidate(hasCompletedHomeTourProvider);
          },
        ),
      ),
      // Landing page route (new users)
      GoRoute(
        path: '/',
        name: 'landing',
        builder: (context, state) => const LandingScreen(),
      ),
      // Home route (logged-in users)
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) {
          // Support ?chat_id=X for returning from Stripe checkout, quick-create,
          // invite joins, and push taps. ?share=1 reopens the invite dialog
          // (used by quick-create so a refresh restores the chat + its prompt).
          final chatIdParam = state.uri.queryParameters['chat_id'];
          final returnToChatId = chatIdParam != null ? int.tryParse(chatIdParam) : null;
          final shareOnOpen = state.uri.queryParameters['share'] == '1';
          // ?instant=1 (official-chat auto-join): veil Home behind a spinner
          // until the chat pushes — URL → chat with no Home flash.
          final instantOpen = state.uri.queryParameters['instant'] == '1';
          return HomeScreen(
              returnToChatId: returnToChatId,
              shareOnOpen: shareOnOpen,
              instantOpen: instantOpen);
        },
      ),
      // Landing-CTA chat creator. Renders Home with autoCreate:true, which opens
      // the full CreateChatWizard on top of Home. Home (not a bare wizard route)
      // must be the base: the wizard pops its result back to its caller, which
      // then opens the new chat + refreshes the list. Pointing /create straight
      // at the wizard popped into an empty stack -> blank screen (chat created
      // but never shown). See HomeScreen.autoCreate / _openCreateChat.
      GoRoute(
        path: '/create',
        name: 'create',
        builder: (context, state) => const HomeScreen(autoCreate: true),
      ),
      // Action picker (FAB) — must be a go_router route, not Navigator.push,
      // so context.go() from a child route (e.g. Discover after joining)
      // clears it from the stack instead of leaving it stranded on top.
      GoRoute(
        path: '/actions',
        name: 'actions',
        builder: (context, state) => const ActionPickerScreen(),
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
      // Value-first tap-vote demo (new landing-CTA target)
      GoRoute(
        path: '/try',
        name: 'try',
        builder: (context, state) => const DemoVoteScreen(),
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
      // Legacy wedge chat links: the Next.js wedge (live on onemind.life
      // 2026-06-07 → 2026-07-04) shared chats as /c/CODE. Route them into the
      // join flow — existing participants get re-opened into the chat there,
      // newcomers get the join form.
      GoRoute(
        path: '/c/:code',
        name: 'wedge-chat-code',
        redirect: (context, state) =>
            '/join/${state.pathParameters['code'] ?? ''}',
      ),
      // Legacy wedge game-mode landing: no game mode in this app — send to
      // the create flow, its closest equivalent.
      GoRoute(
        path: '/game',
        name: 'wedge-game',
        redirect: (context, state) => '/create',
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
      // Blog
      GoRoute(
        path: '/blog',
        name: 'blog',
        builder: (context, state) => const BlogIndexScreen(),
      ),
      GoRoute(
        path: '/blog/:slug',
        name: 'blog-post',
        builder: (context, state) {
          final slug = state.pathParameters['slug'] ?? '';
          final post = blogPosts.cast<BlogPost?>().firstWhere(
                (p) => p!.slug == slug,
                orElse: () => null,
              );
          if (post == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Not Found')),
              body: const Center(child: Text('Article not found.')),
            );
          }
          return BlogPostScreen(post: post);
        },
      ),
      // SEO keyword landing pages
      ...seoPages.entries.map(
        (entry) => GoRoute(
          path: '/${entry.key}',
          name: entry.key,
          builder: (context, state) => SeoLandingPage(data: entry.value),
        ),
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
  return router;
});
