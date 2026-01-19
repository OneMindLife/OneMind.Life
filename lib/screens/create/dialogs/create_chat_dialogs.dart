import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/models.dart';
import '../../../widgets/qr_code_share.dart';

/// Dialog helpers for the create chat screen
class CreateChatDialogs {
  /// Shows timer warning dialog when timer exceeds schedule window
  static Future<bool> showTimerWarning(
    BuildContext context,
    int windowMinutes,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Timer Warning'),
            content: Text(
              'Your phase timers are longer than the $windowMinutes-minute schedule window.\n\n'
              'Phases may extend beyond the scheduled time, or pause when the window closes.\n\n'
              'Consider using shorter timers (5 min or 30 min) for scheduled sessions.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Adjust Settings'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue Anyway'),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chat Created!'),
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
            child: const Text('Continue'),
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
          'Your chat is now public!',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Anyone can find and join "${chat.name}" from the Discover page.',
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
              ? '$invitesSent invite${invitesSent == 1 ? '' : 's'} sent!'
              : 'No invites sent',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Only invited users can join this chat.',
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
    final colorScheme = Theme.of(dialogContext).colorScheme;
    final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Share this code with participants:'),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: chat.inviteCode ?? ''));
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(
                content: Text('Invite code copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chat.inviteCode ?? 'N/A',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: isDark
                          ? colorScheme.onSurface
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.copy,
                    size: 24,
                    color: isDark
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onPrimaryContainer.withAlpha(180),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap to copy',
          style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            QrCodeShareDialog.show(
              parentContext,
              chatName: chat.name,
              inviteCode: chat.inviteCode!,
            ).then((_) => onContinue());
          },
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Show QR Code'),
        ),
      ],
    );
  }
}
