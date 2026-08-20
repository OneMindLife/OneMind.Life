import 'package:flutter/widgets.dart';

import '../services/remote_log_service.dart';

/// TEMPORARY DIAGNOSTIC (2026-06-07) — remote-logs every route transition to
/// `client_logs` so we can reconstruct how users end up stranded on marketing
/// pages (the "created a chat → browser-back → landing → CTA → demo" trap).
///
/// Captures the TRIGGER (push / pop / replace) — `pop` ≈ the browser/system
/// back button, which is the suspected cause — plus from/to route names and the
/// resulting stack depth. Query with:
///   SELECT created_at, message, metadata FROM client_logs
///   WHERE event = 'route_change' ORDER BY created_at DESC;
///
/// Fire-and-forget (RemoteLog swallows errors), so it never blocks navigation.
/// REMOVE once the navigation trap is understood + fixed.
class RouteTransitionLogger extends NavigatorObserver {
  void _log(String trigger, Route<dynamic>? to, Route<dynamic>? from) {
    final toName = to?.settings.name ?? '(unnamed)';
    final fromName = from?.settings.name ?? '(none)';
    RemoteLog.log(
      'route_change',
      '$trigger: $fromName -> $toName',
      {
        'trigger': trigger,
        'from': fromName,
        'to': toName,
      },
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // `route` is the page being popped OFF; after the pop we land on
    // `previousRoute`. So from = the page leaving, to = where we end up.
    _log('pop', previousRoute, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _log('replace', newRoute, oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('remove', previousRoute, route);
  }
}
