import 'package:flutter/foundation.dart';

/// Sealed-loop guard for quick chats (D37 interim fix).
///
/// When a host creates a quick chat we stash its id here. go_router's `redirect`
/// consults it: any navigation to a funnel/marketing route (landing `/`, an SEO
/// page, `/create`, `/demo`, `/try`) while this is set is bounced back to the
/// chat (`/home?chat_id=<id>`) — implementing the sealed-loop model ("the only
/// forward exit is the chat's 'Create a new chat' button").
///
/// WHY a redirect guard and not "don't add to history": verified by automated
/// experiment (Playwright, all four go_router primitives) that go_router 17 on
/// web adds a browser-history entry for EVERY navigation — go/push/replace/
/// pushReplacement, no exception. So OS/browser-back can't be made to "exit" by
/// collapsing history; the only true no-history nav is `window.location.replace`
/// (a full page reload, which sacrifices the SPA-reveal speed optimization). The
/// real fix is migrating the quick-chat wedge to Next.js, where native routing
/// makes back/replace behave correctly (decisions D37/D38). This guard is the
/// interim that stops the bleeding without the rebuild.
///
/// Set by `QuickCreateScreen` right after the chat is created; cleared by the
/// chat-end "Create a new chat" button. In-memory by design: a full reload
/// starts with clean history anyway, so the trap can't recur after a reload.
final ValueNotifier<int?> activeQuickChatId = ValueNotifier<int?>(null);

/// Pure guard logic (unit-tested). Given the [location] being navigated to, the
/// [activeChatId] (null when no quick chat is active), and [isSeoSlug] (true if
/// a bare slug is one of the SEO landing pages), returns the redirect target
/// — `/home?chat_id=<id>` — when the destination is a funnel/marketing route
/// that should bounce back to the active quick chat, or null to allow the nav.
String? quickChatGuardRedirect(
  String location,
  int? activeChatId,
  bool Function(String slug) isSeoSlug,
) {
  if (activeChatId == null) return null;
  final slug = location.replaceFirst('/', '');
  final isFunnelRoute = location == '/' ||
      location == '/create' ||
      location == '/demo' ||
      location == '/try' ||
      isSeoSlug(slug);
  return isFunnelRoute ? '/home?chat_id=$activeChatId' : null;
}
