import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/join/invite_join_screen.dart';
import '../screens/legal/legal_document_screen.dart';
import '../screens/demo/demo_screen.dart';
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

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    observers: observer != null ? [observer] : [],
    // Redirect first-time users to tutorial
    redirect: (context, state) {
      updateMetaTags(state.matchedLocation);
      final isGoingToTutorial = state.matchedLocation == '/tutorial';
      final isJoinRoute = state.matchedLocation.startsWith('/join');
      final isLegalRoute = state.matchedLocation == '/privacy' ||
          state.matchedLocation == '/terms';
      final isDemoRoute = state.matchedLocation == '/demo';

      // Don't redirect if already going to tutorial
      if (isGoingToTutorial) return null;

      // Don't redirect join routes (user is joining via invite link)
      if (isJoinRoute) return null;

      // Don't redirect legal routes (accessible from tutorial)
      if (isLegalRoute) return null;

      // Don't redirect demo route (accessible without tutorial)
      if (isDemoRoute) return null;

      // Redirect to tutorial if not completed
      if (!hasCompletedTutorial) {
        return '/tutorial';
      }

      return null;
    },
    routes: [
      // Tutorial route
      GoRoute(
        path: '/tutorial',
        name: 'tutorial',
        builder: (context, state) => TutorialScreen(
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

              // Mark tutorial as complete FIRST so user is never stuck
              // on a broken tutorial screen if network calls fail
              ref.read(tutorialServiceProvider).markTutorialComplete();

              // Invalidate the provider to trigger rebuild
              // This will cause the router to rebuild and navigate to '/' automatically
              ref.invalidate(hasCompletedTutorialProvider);

              if (!isFirstTime) {
                // Returning user - just navigate back to Home
                await Future.delayed(const Duration(milliseconds: 100));
                rootNavigatorKey.currentState?.pop();
                return;
              }

              // First-time user: auto-join official chat and navigate

              // Check if user came via join link
              final pendingJoinChatId = ref.read(pendingJoinChatIdProvider);

              // Clear the pending join chat ID immediately
              ref.read(pendingJoinChatIdProvider.notifier).state = null;

              final chatService = ref.read(chatServiceProvider);
              final participantService = ref.read(participantServiceProvider);

              // 1. AUTO-JOIN to official public chat (no display name for public)
              Chat? officialChat;
              try {
                officialChat = await chatService.getOfficialChat();
                if (officialChat != null) {
                  await participantService.joinPublicChat(
                      chatId: officialChat.id);
                  // Refetch to get the updated chat with participant
                  officialChat = await chatService.getOfficialChat();
                }
              } catch (e) {
                // Ignore errors (already joined, network issue, etc.)
                // User can still use the app without the official chat
              }

              // 2. Fetch user's chats and pending requests
              Chat? approvedChat;
              bool hasPendingInvite = false;
              try {
                final chats = await chatService.getMyChats();
                final pendingRequests =
                    await participantService.getMyPendingRequests();

                // 3. Check invite status
                if (pendingJoinChatId != null) {
                  approvedChat = chats
                      .where((c) => c.id == pendingJoinChatId)
                      .firstOrNull;
                  hasPendingInvite =
                      pendingRequests.any((r) => r.chatId == pendingJoinChatId);
                }
              } catch (e) {
                // Network error fetching chats - user goes to Home anyway
              }

              // Wait for router to rebuild and home screen to mount
              await Future.delayed(const Duration(milliseconds: 300));
              final navigatorState = rootNavigatorKey.currentState;
              if (navigatorState == null) {
                return;
              }

              // 4. Navigate based on conditions
              if (approvedChat != null) {
                // User came via invite and was approved - go to invited chat
                await navigatorState.push(
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(chat: approvedChat!),
                  ),
                );
              } else if (hasPendingInvite) {
                // User came via invite but pending - stay on Home
                // (shows public chat + pending request)
              } else if (officialChat != null) {
                // No invite context - go to official public chat
                await navigatorState.push(
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(chat: officialChat!),
                  ),
                );
              }
              // Fallback: stay on Home (e.g., if official chat doesn't exist)
            } finally {
              // Reset guard after completion
              _tutorialCompletionInProgress = false;
            }
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
      return Scaffold(
        appBar: AppBar(title: const Text('Page Not Found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                state.uri.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    },
  );
});
