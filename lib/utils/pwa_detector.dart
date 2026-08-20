/// Cross-platform PWA detection. Returns true only when the Flutter
/// web build is launched from an installed PWA (standalone display-mode).
/// Always false on Android/iOS/desktop.
library;

export 'pwa_detector_stub.dart'
    if (dart.library.html) 'pwa_detector_web.dart';
