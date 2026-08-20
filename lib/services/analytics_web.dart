import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Send a gtag page_view via the JS helper defined in index.html.
///
/// GA4 web streams use page_view events (not screen_view) for the
/// "2+ page views → engaged session" criterion. This bridges Flutter
/// route changes to gtag so in-app-browser sessions register as engaged.
void sendWebPageView(String path, String title) {
  try {
    final fn = globalContext.getProperty('_onemindPageView'.toJS);
    if (fn.isA<JSFunction>()) {
      (fn as JSFunction).callAsFunction(null, path.toJS, title.toJS);
    }
  } catch (_) {
    // Non-critical — analytics only
  }
}

/// Fire a custom analytics event via gtag.js (not the Firebase Analytics
/// web plugin). The plugin silently dropped chat/proposition/rating
/// events after a Firebase JS SDK update; gtag.js is the same pipeline
/// that splash_shown / flutter_loaded use and is verified to flow.
void sendWebEvent(String name, Map<String, Object?> parameters) {
  try {
    final fn = globalContext.getProperty('_onemindLogEvent'.toJS);
    if (!fn.isA<JSFunction>()) return;
    final filtered = <String, Object>{};
    parameters.forEach((k, v) {
      if (v != null) filtered[k] = v;
    });
    (fn as JSFunction).callAsFunction(
      null,
      name.toJS,
      jsonEncode(filtered).toJS,
    );
  } catch (_) {
    // Non-critical — analytics only
  }
}

/// Report a Flutter/Dart exception to PostHog error tracking via the
/// window._onemindCaptureException bridge in index.html (which calls
/// posthog.captureException). PostHog links the error to the session replay.
void sendWebException(String type, String message, String? stack) {
  try {
    final fn = globalContext.getProperty('_onemindCaptureException'.toJS);
    if (!fn.isA<JSFunction>()) return;
    (fn as JSFunction).callAsFunction(
      null,
      type.toJS,
      message.toJS,
      stack?.toJS,
    );
  } catch (_) {
    // Error reporting must never throw.
  }
}
