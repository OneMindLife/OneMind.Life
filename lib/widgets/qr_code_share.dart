import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/env_config.dart';

/// A dialog that displays a QR code for sharing a chat invite.
class QrCodeShareDialog extends StatelessWidget {
  final String chatName;
  final String inviteCode;
  final String? deepLinkUrl;

  const QrCodeShareDialog({
    super.key,
    required this.chatName,
    required this.inviteCode,
    this.deepLinkUrl,
  });

  /// Show the QR code share dialog.
  static Future<void> show(
    BuildContext context, {
    required String chatName,
    required String inviteCode,
    String? deepLinkUrl,
  }) {
    return showDialog(
      context: context,
      builder: (context) => QrCodeShareDialog(
        chatName: chatName,
        inviteCode: inviteCode,
        deepLinkUrl: deepLinkUrl,
      ),
    );
  }

  String get _qrData {
    // For web app: encode the join URL
    return deepLinkUrl ?? '${EnvConfig.webAppUrl}/join/$inviteCode';
  }

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite code copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.qr_code_2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Join $chatName',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Invite code display (moved to top)
            Text(
              'Share code:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _copyCode(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withAlpha(50),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      inviteCode,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        color: isDark
                            ? colorScheme.onSurface
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.copy,
                      size: 20,
                      color: isDark
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onPrimaryContainer.withAlpha(180),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to copy',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),

            // Divider with "or"
            Row(
              children: [
                Expanded(child: Divider(color: colorScheme.outline)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'or scan',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(child: Divider(color: colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 16),

            // QR Code
            // IgnorePointer prevents QR code from blocking mouse events
            IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
