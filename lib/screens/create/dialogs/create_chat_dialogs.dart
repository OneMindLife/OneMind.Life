import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../../widgets/qr_code_share.dart';

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

  /// Shows success dialog after chat creation.
  ///
  /// For public and code-based chats (which have invite codes), shows the
  /// same QrCodeShareDialog used by the share button in the chat app bar.
  /// For invite-only chats (no invite code), shows a simple confirmation.
  static void showSuccess({
    required BuildContext context,
    required Chat chat,
    required AccessMethod accessMethod,
    required int invitesSent,
    required VoidCallback onContinue,
  }) {
    if (chat.inviteCode != null) {
      // Public and code-based chats: reuse the same share dialog
      // shown by the share button in the chat app bar
      QrCodeShareDialog.show(
        context,
        chatName: chat.name,
        inviteCode: chat.inviteCode!,
        barrierDismissible: false,
      ).then((_) => onContinue());
      return;
    }

    // Invite-only chats: no invite code to share, show simple confirmation
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chatCreatedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              size: 48,
              color: Theme.of(dialogContext).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              invitesSent > 0
                  ? l10n.invitesSentTitle(invitesSent)
                  : l10n.noInvitesSentTitle,
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.inviteOnlyMessage,
              style: Theme.of(dialogContext).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onContinue();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(l10n.continue_,
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
