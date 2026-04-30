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
