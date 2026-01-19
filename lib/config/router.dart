import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/join/invite_join_screen.dart';

/// App router configuration
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    debugLogDiagnostics: true,
    routes: [
      // Home route
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
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
        builder: (context, state) {
          final code = state.pathParameters['code'];
          return InviteJoinScreen(code: code);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
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
    ),
  );
});
