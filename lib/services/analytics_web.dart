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
