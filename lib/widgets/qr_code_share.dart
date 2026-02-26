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
    bool barrierDismissible = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => QrCodeShareDialog(
        chatName: chatName,
        inviteCode: inviteCode,
        deepLinkUrl: deepLinkUrl,
      ),
    );
  }

  String get _fullUrl {
    return deepLinkUrl ?? '${EnvConfig.webAppUrl}/join/$inviteCode';
  }

  Future<void> _copyLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _fullUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.linkCopied),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      await Share.share(
        _fullUrl,
        subject: l10n.shareLinkTitle(chatName),
      );
    } catch (_) {
      // Fallback: copy to clipboard if share fails
      if (context.mounted) await _copyLink(context);
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
          Expanded(
            child: Text(
              l10n.shareLinkTitle(chatName),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // URL with copy button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                left: 12,
                top: 4,
                bottom: 4,
                right: 4,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fullUrl,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.primary,
                            fontFamily: 'monospace',
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: l10n.linkCopied,
                    onPressed: () => _copyLink(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Share button (opens native share sheet)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _shareLink(context),
                icon: const Icon(Icons.share),
                label: Text(l10n.shareButton),
              ),
            ),
            const SizedBox(height: 8),

            // Collapsible QR code + manual code section
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                title: Text(
                  l10n.orScan,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                children: [
                  // QR Code
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        inviteCode,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  color: colorScheme.primary,
                                ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: l10n.codeCopied,
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: inviteCode),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.codeCopied),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: EdgeInsets.zero,
    );
  }
}
