import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/error_view.dart';
import '../screens/discover/discover_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/blog/blog_data.dart';
import '../screens/blog/blog_index_screen.dart';
import '../screens/blog/blog_post_screen.dart';
import '../screens/landing/seo_landing_page.dart';
import '../screens/landing/seo_pages.dart';
import '../screens/join/invite_join_screen.dart';
import '../screens/legal/legal_document_screen.dart';
import '../screens/action_picker/action_picker_screen.dart';
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
  final hasCompletedHomeTour = ref.watch(hasCompletedHomeTourProvider);

  late final GoRouter router;
  router = GoRouter(
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
        return '/';
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
