import 'package:web/web.dart' as web;

/// True when running inside an installed PWA (standalone display-mode).
/// Falls back to false on any failure to keep startup robust.
bool isStandalonePwa() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}
