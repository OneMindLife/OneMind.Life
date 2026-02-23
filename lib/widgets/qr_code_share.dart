import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/env_config.dart';
import '../l10n/generated/app_localizations.dart';

/// A dialog that displays a QR code for sharing a chat invite.
class QrCodeShareDialog extends StatelessWidget {
  final String chatName;
  final String inviteCode;
  final String? deepLinkUrl;

  /// If true, shows a prominent "Continue" button instead of small "Done" text.
  /// Use this for tutorial mode to make it clear users need to tap to proceed.
  final bool showContinueButton;

  const QrCodeShareDialog({
    super.key,
    required this.chatName,
    required this.inviteCode,
    this.deepLinkUrl,
    this.showContinueButton = false,
  });

  /// Show the QR code share dialog.
  static Future<void> show(
    BuildContext context, {
    required String chatName,
    required String inviteCode,
    String? deepLinkUrl,
    bool showContinueButton = false,
    bool barrierDismissible = true,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => QrCodeShareDialog(
        chatName: chatName,
        inviteCode: inviteCode,
        deepLinkUrl: deepLinkUrl,
        showContinueButton: showContinueButton,
      ),
    );
  }

  String get _fullUrl {
    return deepLinkUrl ?? '${EnvConfig.webAppUrl}/join/$inviteCode';
  }

  /// Copies link to clipboard and also opens native share sheet if available.
  Future<void> _copyAndShare(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    // Always copy to clipboard first
    await Clipboard.setData(ClipboardData(text: _fullUrl));

    // Show feedback that link was copied
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.linkCopied),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Also try to open native share sheet (works on mobile, no-op on desktop)
    try {
      await Share.share(
        _fullUrl,
        subject: l10n.shareLinkTitle(chatName),
      );
    } catch (e) {
      // Ignore share errors - link is already copied
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.share),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.shareLinkTitle(chatName),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Full URL display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                ),
              ),
              child: SelectableText(
                _fullUrl,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
              ),
            ),
            const SizedBox(height: 16),

            // Share button (copies to clipboard + opens share sheet on mobile)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _copyAndShare(context),
                icon: const Icon(Icons.share),
                label: Text(l10n.shareButton),
              ),
            ),
            const SizedBox(height: 20),

            // Divider with "or scan"
            Row(
              children: [
                Expanded(child: Divider(color: colorScheme.outline)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.orScan,
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
                  width: 180,
                  height: 180,
                  child: QrImageView(
                    data: _fullUrl,
                    version: QrVersions.auto,
                    size: 180,
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
            const SizedBox(height: 16),

            // Manual code fallback
            Text(
              l10n.enterCodeManually,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              inviteCode,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        if (showContinueButton)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l10n.continue_,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l10n.done,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
