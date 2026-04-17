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
