import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onemind_app/config/router.dart';

void main() {
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    container = ProviderContainer();
    router = container.read(routerProvider);
  });

  tearDown(() {
    container.dispose();
  });

  group('Router Configuration', () {
    test('has home route at /', () {
      final match = router.configuration.findMatch(Uri.parse('/'));
      expect(match, isNotNull);
      expect(match.uri.toString(), '/');
    });

    test('has join-invite route at /join/invite', () {
      final match = router.configuration.findMatch(Uri.parse('/join/invite'));
      expect(match, isNotNull);
      expect(match.uri.toString(), '/join/invite');
    });

    test('parses token query parameter for join-invite', () {
      final match =
          router.configuration.findMatch(Uri.parse('/join/invite?token=abc-123'));
      expect(match, isNotNull);
      expect(match.uri.queryParameters['token'], 'abc-123');
    });

    test('has join-code route at /join/:code', () {
      final match = router.configuration.findMatch(Uri.parse('/join/ABCDEF'));
      expect(match, isNotNull);
      expect(match.pathParameters['code'], 'ABCDEF');
    });

    test('handles unknown routes with error page', () {
      // Unknown routes should still match but render error builder
      final match = router.configuration.findMatch(Uri.parse('/unknown/route'));
      // The error builder handles this case
      expect(match.uri.toString(), '/unknown/route');
    });
  });

  group('Route Names', () {
    test('home route is named "home"', () {
      final routes = router.configuration.routes;
      final homeRoute = routes.firstWhere(
        (r) => r is GoRoute && r.name == 'home',
        orElse: () => throw Exception('Home route not found'),
      );
      expect(homeRoute, isA<GoRoute>());
    });

    test('join-invite route is named "join-invite"', () {
      final routes = router.configuration.routes;
      final joinInviteRoute = routes.firstWhere(
        (r) => r is GoRoute && r.name == 'join-invite',
        orElse: () => throw Exception('Join-invite route not found'),
      );
      expect(joinInviteRoute, isA<GoRoute>());
    });

    test('join-code route is named "join-code"', () {
      final routes = router.configuration.routes;
      final joinCodeRoute = routes.firstWhere(
        (r) => r is GoRoute && r.name == 'join-code',
        orElse: () => throw Exception('Join-code route not found'),
      );
      expect(joinCodeRoute, isA<GoRoute>());
    });
  });

  group('URL Parsing', () {
    test('parses invite token from URL', () {
      final url = Uri.parse('/join/invite?token=550e8400-e29b-41d4-a716-446655440000');
      final match = router.configuration.findMatch(url);
      expect(match.uri.queryParameters['token'],
          '550e8400-e29b-41d4-a716-446655440000');
    });

    test('parses invite code from path', () {
      final url = Uri.parse('/join/XYZ789');
      final match = router.configuration.findMatch(url);
      expect(match.pathParameters['code'], 'XYZ789');
    });

    test('handles URL with multiple query params', () {
      final url = Uri.parse('/join/invite?token=abc-123&extra=ignored');
      final match = router.configuration.findMatch(url);
      expect(match.uri.queryParameters['token'], 'abc-123');
      expect(match.uri.queryParameters['extra'], 'ignored');
    });
  });
}
