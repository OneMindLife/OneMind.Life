import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../widgets/error_view.dart';
import 'invite_code_parser.dart';

export 'invite_code_parser.dart' show extractInviteCode;

// Conditionally import native scanner support
import 'barcode_detector_stub.dart'
    if (dart.library.js_interop) 'barcode_detector_web.dart' as detector;

/// Fullscreen QR scanner that detects invite codes and returns them.
/// Uses native BarcodeDetector API on supported browsers (Chrome 83+),
/// falls back to mobile_scanner on others (Firefox, Safari).
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _hasScanned = false;
  late final bool _useNative;
  MobileScannerController? _fallbackController;

  @override
  void initState() {
    super.initState();
    _useNative = kIsWeb && detector.isBarcodeDetectorSupported;
    if (!_useNative) {
      _fallbackController = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _fallbackController?.dispose();
    super.dispose();
  }

  void _onCodeDetected(String rawValue) {
    if (_hasScanned) return;
    final code = extractInviteCode(rawValue);
    if (code != null) {
      _hasScanned = true;
      Navigator.pop(context, code);
      return;
    }
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      context.showInfoSnackBar(l10n.invalidQrCode);
    }
  }

  void _onMobileScannerDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) {
        _onCodeDetected(raw);
        return;
      }
    }
  }

  Widget _buildError(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(l10n.cameraPermissionDenied, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackScanner() {
    return MobileScanner(
      controller: _fallbackController!,
      onDetect: _onMobileScannerDetect,
      errorBuilder: (ctx, err, _) => _buildError(ctx, err),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanQrCode)),
      body: Stack(
        children: [
          _useNative
              ? detector.buildNativeScanner(
                  onDetect: _onCodeDetected,
                  errorBuilder: _buildError,
                )
              : _buildFallbackScanner(),
          _ScanOverlay(hint: l10n.pointCameraAtQrCode),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay widgets (platform-agnostic)
// ---------------------------------------------------------------------------

class _ScanOverlay extends StatelessWidget {
  final String hint;
  const _ScanOverlay({required this.hint});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scanSize = constraints.maxWidth * 0.65;
      final top = (constraints.maxHeight - scanSize) / 2 - 40;
      return Stack(children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
          child: Stack(children: [
            Positioned.fill(child: Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut))),
            Positioned(top: top, left: (constraints.maxWidth - scanSize) / 2,
              child: Container(width: scanSize, height: scanSize,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)))),
          ]),
        ),
        Positioned(top: top, left: (constraints.maxWidth - scanSize) / 2, child: _ScanCorners(size: scanSize)),
        Positioned(top: top + scanSize + 24, left: 0, right: 0,
          child: Text(hint, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white, shadows: [const Shadow(blurRadius: 4, color: Colors.black)]))),
      ]);
    });
  }
}

class _ScanCorners extends StatelessWidget {
  final double size;
  const _ScanCorners({required this.size});

  @override
  Widget build(BuildContext context) {
    const cl = 30.0, t = 3.0;
    final c = Theme.of(context).colorScheme.primary;
    Widget corner(Alignment a, BorderRadius br) => Align(alignment: a,
      child: Container(width: cl, height: cl, decoration: BoxDecoration(
        border: Border(
          top: a.y < 0 ? BorderSide(color: c, width: t) : BorderSide.none,
          bottom: a.y > 0 ? BorderSide(color: c, width: t) : BorderSide.none,
          left: a.x < 0 ? BorderSide(color: c, width: t) : BorderSide.none,
          right: a.x > 0 ? BorderSide(color: c, width: t) : BorderSide.none),
        borderRadius: br)));
    return SizedBox(width: size, height: size, child: Stack(children: [
      corner(Alignment.topLeft, const BorderRadius.only(topLeft: Radius.circular(16))),
      corner(Alignment.topRight, const BorderRadius.only(topRight: Radius.circular(16))),
      corner(Alignment.bottomLeft, const BorderRadius.only(bottomLeft: Radius.circular(16))),
      corner(Alignment.bottomRight, const BorderRadius.only(bottomRight: Radius.circular(16))),
    ]));
  }
}
