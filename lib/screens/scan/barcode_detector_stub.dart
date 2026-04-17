import 'package:flutter/material.dart';

/// Stub for non-web platforms.
bool get isBarcodeDetectorSupported => false;

/// Stub — should never be called on non-web.
Widget buildNativeScanner({
  required void Function(String) onDetect,
  required Widget Function(BuildContext, Object) errorBuilder,
}) {
  throw UnsupportedError('NativeBarcodeScanner is only available on web');
}
