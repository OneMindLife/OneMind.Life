import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Returns true if the user tapped the HTML play button before Flutter loaded.
bool wasHtmlPlayTapped() {
  try {
    final val = globalContext.getProperty('_htmlPlayTapped'.toJS);
    if (val.isA<JSBoolean>()) {
      return (val as JSBoolean).toDart;
    }
  } catch (_) {}
  return false;
}

/// Register a Dart callback that the HTML play button can invoke.
/// When the user taps play on the HTML screen after Flutter is already loaded,
/// this callback auto-advances past the Flutter intro.
void registerHtmlPlayCallback(void Function() onPlay) {
  globalContext.setProperty(
    '_flutterAutoAdvance'.toJS,
    (() { onPlay(); }).toJS,
  );
}

/// Remove the registered callback (cleanup on dispose).
void unregisterHtmlPlayCallback() {
  try {
    globalContext.setProperty('_flutterAutoAdvance'.toJS, null);
  } catch (_) {}
}

/// Returns true if the user tapped the HTML skip button before Flutter loaded.
bool wasHtmlSkipTapped() {
  try {
    final val = globalContext.getProperty('_htmlSkipTapped'.toJS);
    if (val.isA<JSBoolean>()) {
      return (val as JSBoolean).toDart;
    }
  } catch (_) {}
  return false;
}

/// Register a Dart callback that the HTML skip button can invoke.
/// When the user taps skip on the HTML screen after Flutter is already loaded,
/// this callback finishes the tutorial and navigates home without the
/// confirmation dialog.
void registerHtmlSkipCallback(void Function() onSkip) {
  globalContext.setProperty(
    '_flutterAutoSkip'.toJS,
    (() { onSkip(); }).toJS,
  );
}

/// Remove the registered skip callback (cleanup on dispose).
void unregisterHtmlSkipCallback() {
  try {
    globalContext.setProperty('_flutterAutoSkip'.toJS, null);
  } catch (_) {}
}

/// Register a Dart callback that the HTML legal links can invoke.
/// When the user taps Terms/Privacy in the HTML play screen after Flutter
/// is already loaded, this callback navigates GoRouter to the legal page
/// (history.replaceState alone doesn't fire popstate, so go_router would
/// otherwise keep rendering the tutorial).
void registerHtmlLegalCallback(void Function(String page) onLegal) {
  globalContext.setProperty(
    '_flutterAutoLegal'.toJS,
    ((JSString page) { onLegal(page.toDart); }).toJS,
  );
}

/// Remove the registered legal callback (cleanup on dispose).
void unregisterHtmlLegalCallback() {
  try {
    globalContext.setProperty('_flutterAutoLegal'.toJS, null);
  } catch (_) {}
}

/// Register a Dart callback the HTML hero "Try It Free" CTA invokes to enter
/// the app WITHOUT a full page reload.
///
/// Flutter boots behind the HTML hero while the user reads it. On tap, the
/// shell calls `window._flutterGoCreate(target)` so go_router navigates
/// straight to [target] (e.g. `/create?gclid=…`, query string preserved for
/// attribution) and the already-rendered app is simply uncovered — no second
/// cold start, no loading splash.
void registerHtmlCreateCallback(void Function(String target) onCreate) {
  globalContext.setProperty(
    '_flutterGoCreate'.toJS,
    ((JSString target) {
      onCreate(target.toDart);
    }).toJS,
  );
}

/// Remove the registered create callback (cleanup on dispose).
void unregisterHtmlCreateCallback() {
  try {
    globalContext.setProperty('_flutterGoCreate'.toJS, null);
  } catch (_) {}
}

/// Tell the HTML shell that Flutter has painted its first frame.
///
/// `index.html` keeps the loading splash up until this fires. The splash used
/// to be torn down the moment Flutter's `flutter-view` element appeared, but
/// that element is inserted during *engine init* — before any frame paints —
/// so the SEO-content backdrop (which embeds the demo video) flashed through
/// the gap, especially on PWA launches that start at `/home`. Signalling from
/// a post-frame callback closes that gap. Safe to call in any launch mode:
/// the JS handler only removes `#splash`, which is hidden in hero/play modes.
void signalFlutterFirstFrame() {
  try {
    final fn = globalContext.getProperty('_onFlutterFirstFrame'.toJS);
    if (fn.isA<JSFunction>()) {
      (fn as JSFunction).callAsFunction();
    }
  } catch (_) {}
}
