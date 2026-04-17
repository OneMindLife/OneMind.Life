import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// ---------------------------------------------------------------------------
// JS interop bindings for BarcodeDetector
// ---------------------------------------------------------------------------

@JS('globalThis.BarcodeDetector')
external JSFunction? get _barcodeDetectorConstructor;

/// Checks if the browser supports the BarcodeDetector API.
bool get isBarcodeDetectorSupported => _barcodeDetectorConstructor != null;

extension type _JsBarcodeDetector(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSObject>> detect(JSObject source);
}

@JS('Reflect.construct')
external JSObject _reflectConstruct(JSFunction target, JSArray<JSAny> args);

_JsBarcodeDetector _createDetector() {
  final wrappedOptions = {'formats': ['qr_code'].jsify()!}.jsify()!;
  final args = <JSAny>[wrappedOptions].toJS;
  return _reflectConstruct(_barcodeDetectorConstructor!, args)
      as _JsBarcodeDetector;
}

String _getRawValue(JSObject barcode) {
  final dartified = (barcode as JSAny).dartify();
  if (dartified is Map) {
    return dartified['rawValue']?.toString() ?? '';
  }
  return '';
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// A QR scanner widget that uses the native browser BarcodeDetector API.
/// Much faster than JS-based decoding on supported browsers (Chrome 83+, Edge, Opera).
class NativeBarcodeScanner extends StatefulWidget {
  final void Function(String rawValue) onDetect;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const NativeBarcodeScanner({
    super.key,
    required this.onDetect,
    this.errorBuilder,
  });

  @override
  State<NativeBarcodeScanner> createState() => _NativeBarcodeScannerState();
}

class _NativeBarcodeScannerState extends State<NativeBarcodeScanner> {
  static int _viewIdCounter = 0;

  late final String _viewId;
  late final web.HTMLVideoElement _video;
  web.MediaStream? _stream;
  Timer? _scanTimer;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewId = 'native-barcode-scanner-${_viewIdCounter++}';
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    ui_web.platformViewRegistry
        .registerViewFactory(_viewId, (int viewId) => _video);

    _startCamera();
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  Future<void> _startCamera() async {
    try {
      final constraints = web.MediaStreamConstraints(
        video: {
          'facingMode': 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        }.jsify()!,
      );

      _stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      _video.srcObject = _stream;

      if (mounted) {
        setState(() => _initialized = true);
      }

      _startScanning();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _startScanning() {
    final detector = _createDetector();

    // Scan every 150ms for responsiveness
    _scanTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (!mounted || _video.readyState < 2) return;

      try {
        final results =
            await detector.detect(_video as JSObject).toDart;
        final barcodes = results.toDart;
        for (final barcode in barcodes) {
          final value = _getRawValue(barcode);
          if (value.isNotEmpty) {
            widget.onDetect(value);
            return;
          }
        }
      } catch (_) {
        // Non-fatal — continue scanning
      }
    });
  }

  void _stopCamera() {
    _scanTimer?.cancel();
    _scanTimer = null;

    final tracks = _stream?.getTracks().toDart;
    if (tracks != null) {
      for (final track in tracks) {
        track.stop();
      }
    }
    _stream = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!);
    }

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return HtmlElementView(viewType: _viewId);
  }
}
