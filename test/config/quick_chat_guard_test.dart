import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/config/quick_chat_guard.dart';

/// Unit tests for the D37 sealed-loop guard logic (quickChatGuardRedirect).
/// The guard bounces funnel/marketing navigations back to the active quick chat
/// so OS/browser back can't strand a host on a marketing page.
void main() {
  // Stand-in for seoPages.containsKey: treat these bare slugs as SEO pages.
  bool isSeoSlug(String slug) =>
      {'anonymous-voting-tool', 'consensus-building', 'delphi-method'}
          .contains(slug);

  group('quickChatGuardRedirect', () {
    test('no active chat → never redirects (allows all navigation)', () {
      expect(quickChatGuardRedirect('/create', null, isSeoSlug), isNull);
      expect(quickChatGuardRedirect('/', null, isSeoSlug), isNull);
      expect(quickChatGuardRedirect('/anonymous-voting-tool', null, isSeoSlug),
          isNull);
    });

    group('with an active quick chat (id 489)', () {
      const id = 489;
      const dest = '/home?chat_id=489';

      test('bounces /create back to the chat', () {
        expect(quickChatGuardRedirect('/create', id, isSeoSlug), dest);
      });

      test('bounces the landing page (/) back to the chat', () {
        expect(quickChatGuardRedirect('/', id, isSeoSlug), dest);
      });

      test('bounces the demo routes back to the chat', () {
        expect(quickChatGuardRedirect('/demo', id, isSeoSlug), dest);
        expect(quickChatGuardRedirect('/try', id, isSeoSlug), dest);
      });

      test('bounces SEO landing pages back to the chat', () {
        expect(quickChatGuardRedirect('/anonymous-voting-tool', id, isSeoSlug),
            dest);
        expect(
            quickChatGuardRedirect('/consensus-building', id, isSeoSlug), dest);
      });

      test('does NOT bounce /home (the chat container) — no redirect loop', () {
        expect(quickChatGuardRedirect('/home', id, isSeoSlug), isNull);
      });

      test('does NOT bounce non-funnel routes (join, legal, blog, discover)',
          () {
        expect(quickChatGuardRedirect('/join/ABC123', id, isSeoSlug), isNull);
        expect(quickChatGuardRedirect('/privacy', id, isSeoSlug), isNull);
        expect(quickChatGuardRedirect('/blog/some-post', id, isSeoSlug), isNull);
        expect(quickChatGuardRedirect('/discover', id, isSeoSlug), isNull);
      });
    });
  });
}
