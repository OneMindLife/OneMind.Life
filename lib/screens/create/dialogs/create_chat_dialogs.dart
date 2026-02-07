import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../config/env_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';

/// Dialog helpers for the create chat screen
class CreateChatDialogs {
  /// Shows timer warning dialog when timer exceeds schedule window
  static Future<bool> showTimerWarning(
    BuildContext context,
    int windowMinutes,
  ) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.timerWarningTitle),
            content: Text(
              l10n.timerWarningContent(windowMinutes),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.adjustSettingsButton),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.continueAnywayButton),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Shows success dialog after chat creation
  static void showSuccess({
    required BuildContext context,
    required Chat chat,
    required AccessMethod accessMethod,
    required int invitesSent,
    required VoidCallback onContinue,
  }) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chatCreatedTitle),
        content: _buildSuccessContent(
          dialogContext: dialogContext,
          parentContext: context,
          chat: chat,
          accessMethod: accessMethod,
          invitesSent: invitesSent,
          onContinue: onContinue,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onContinue();
            },
            child: Text(l10n.continue_),
          ),
        ],
      ),
    );
  }

  static Widget _buildSuccessContent({
    required BuildContext dialogContext,
    required BuildContext parentContext,
    required Chat chat,
    required AccessMethod accessMethod,
    required int invitesSent,
    required VoidCallback onContinue,
  }) {
    if (accessMethod == AccessMethod.public) {
      return _buildPublicSuccessContent(dialogContext, chat);
    } else if (accessMethod == AccessMethod.inviteOnly) {
      return _buildInviteOnlySuccessContent(dialogContext, invitesSent);
    } else {
      return _buildCodeSuccessContent(
        dialogContext,
        parentContext,
        chat,
        onContinue,
      );
    }
  }

  static Widget _buildPublicSuccessContent(BuildContext context, Chat chat) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.public,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.chatNowPublicTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.anyoneCanJoinDiscover(chat.name),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static Widget _buildInviteOnlySuccessContent(
    BuildContext context,
    int invitesSent,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          invitesSent > 0
              ? l10n.invitesSentTitle(invitesSent)
              : l10n.noInvitesSentTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.inviteOnlyMessage,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static Widget _buildCodeSuccessContent(
    BuildContext dialogContext,
    BuildContext parentContext,
    Chat chat,
    VoidCallback onContinue,
  ) {
    final l10n = AppLocalizations.of(dialogContext);
    final colorScheme = Theme.of(dialogContext).colorScheme;
    final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
    final inviteCode = chat.inviteCode ?? '';
    final fullUrl = '${EnvConfig.webAppUrl}/join/$inviteCode';

    /// Copies link to clipboard and also opens native share sheet if available.
    Future<void> copyAndShare() async {
      // Always copy to clipboard first
      await Clipboard.setData(ClipboardData(text: fullUrl));

      // Show feedback that link was copied
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(l10n.linkCopied),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Also try to open native share sheet (works on mobile, no-op on desktop)
      try {
        await Share.share(
          fullUrl,
          subject: l10n.shareLinkTitle(chat.name),
        );
      } catch (e) {
        // Ignore share errors - link is already copied
      }
    }

    return SingleChildScrollView(
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
              fullUrl,
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
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
              onPressed: copyAndShare,
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
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              Expanded(child: Divider(color: colorScheme.outline)),
            ],
          ),
          const SizedBox(height: 16),

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
                  data: fullUrl,
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
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            inviteCode,
            style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}
