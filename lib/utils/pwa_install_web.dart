import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the app is running as an installed PWA (standalone mode).
bool isPwaInstalled() {
  try {
    final fn = globalContext.getProperty('_isPwaInstalled'.toJS);
    if (fn.isA<JSFunction>()) {
      final result = (fn as JSFunction).callAsFunction(null);
      return (result as JSBoolean?)?.toDart ?? false;
    }
  } catch (_) {}
  return false;
}

/// Whether the user is on a mobile device.
bool isMobileDevice() {
  try {
    final fn = globalContext.getProperty('_isMobileDevice'.toJS);
    if (fn.isA<JSFunction>()) {
      final result = (fn as JSFunction).callAsFunction(null);
      return (result as JSBoolean?)?.toDart ?? false;
    }
  } catch (_) {}
  return false;
}

/// Whether the user is on iOS.
bool isIos() {
  try {
    final fn = globalContext.getProperty('_isIos'.toJS);
    if (fn.isA<JSFunction>()) {
      final result = (fn as JSFunction).callAsFunction(null);
      return (result as JSBoolean?)?.toDart ?? false;
    }
  } catch (_) {}
  return false;
}

/// Trigger the native PWA install prompt (Android Chrome).
/// Returns true if the user accepted the install.
Future<bool> triggerPwaInstall() async {
  try {
    final fn = globalContext.getProperty('_triggerPwaInstall'.toJS);
    if (fn.isA<JSFunction>()) {
      final result = (fn as JSFunction).callAsFunction(null);
      if (result.isA<JSPromise>()) {
        final jsResult = await (result as JSPromise).toDart;
        if (jsResult.isA<JSBoolean>()) {
          return (jsResult as JSBoolean).toDart;
        }
      }
    }
  } catch (_) {}
  return false;
}

/// Whether the beforeinstallprompt event was captured.
bool hasInstallPrompt() {
  try {
    final fn = globalContext.getProperty('_hasInstallPrompt'.toJS);
    if (fn.isA<JSFunction>()) {
      final result = (fn as JSFunction).callAsFunction(null);
      return (result as JSBoolean?)?.toDart ?? false;
    }
  } catch (_) {}
  return false;
}

/// Check if the PWA is already installed via getInstalledRelatedApps().
/// Returns a Future since the JS API is async.
Future<bool> hasInstalledPwa() async {
  try {
    final fn = globalContext.getProperty('_hasInstalledPwa'.toJS);
    if (fn.isA<JSFunction>()) {
      final result = (fn as JSFunction).callAsFunction(null);
      if (result.isA<JSPromise>()) {
        final jsResult = await (result as JSPromise).toDart;
        if (jsResult.isA<JSBoolean>()) {
          return (jsResult as JSBoolean).toDart;
        }
      }
    }
  } catch (_) {}
  return false;
}
