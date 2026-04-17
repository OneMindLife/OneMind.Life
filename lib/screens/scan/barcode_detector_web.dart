import 'package:flutter/material.dart';

import 'native_barcode_scanner.dart';

export 'native_barcode_scanner.dart' show isBarcodeDetectorSupported;

/// Build the native BarcodeDetector-based scanner widget (web only).
Widget buildNativeScanner({
  required void Function(String) onDetect,
  required Widget Function(BuildContext, Object) errorBuilder,
}) {
  return NativeBarcodeScanner(
    onDetect: onDetect,
    errorBuilder: errorBuilder,
  );
}
