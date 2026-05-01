import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../services/active_audio.dart';
import '../../widgets/error_view.dart';
import '../chat/chat_screen.dart';
import '../create/create_chat_wizard.dart';
import '../join/join_dialog.dart';
import '../scan/qr_scanner_screen.dart';

/// Full-page screen presented when the FAB is tapped.
/// Offers three paths: Discover Chats, Create Chat, Join Chat.
class ActionPickerScreen extends ConsumerWidget {
  const ActionPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.rocket_launch_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.actionPickerTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Order: Discover (lowest friction, "show me what's interesting")
            // → Create (medium, "I have an idea") → Join (highest gating,
            // "I have a code"). Most users arriving here are exploring; the
            // few with a code typically click the invite link directly and
            // bypass this screen.
            _ActionCard(
              icon: Icons.explore,
              title: l10n.actionPickerDiscoverTitle,
              description: l10n.actionPickerDiscoverDesc,
              onTap: () => context.push('/discover'),
            ),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.add_comment,
              title: l10n.actionPickerCreateTitle,
              description: l10n.actionPickerCreateDesc,
              onTap: () => _openCreateChat(context, ref),
            ),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.group_add,
              title: l10n.actionPickerJoinTitle,
              description: l10n.actionPickerJoinDesc,
              onTap: () => _openJoinPicker(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateChat(BuildContext context, WidgetRef ref) async {
    final chat = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(builder: (_) => const CreateChatWizard()),
    );
    if (chat != null && context.mounted) {
      // Pop back to home, then open the new chat
      Navigator.popUntil(context, (route) => route.isFirst);
      ref.read(myChatsProvider.notifier).refresh();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(chat: chat, showShareDialog: true),
        ),
      );
      // ChatScreen.dispose isn't reliable on web — silence chat-scoped
      // audio when returning here.
      ActiveAudio.stopForeground();
      ref.read(backgroundAudioServiceProvider).leaveChat();
    }
  }

  void _openJoinPicker(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _JoinMethodScreen(ref: ref),
      ),
    );
  }
}

/// Second screen: choose how to join (Enter Code or Scan QR).
class _JoinMethodScreen extends ConsumerWidget {
  final WidgetRef ref;

  const _JoinMethodScreen({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.group_add,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.joinMethodTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _ActionCard(
              icon: Icons.keyboard,
              title: l10n.joinMethodCodeTitle,
              description: l10n.joinMethodCodeDesc,
              onTap: () => _openJoinWithCode(context, widgetRef),
            ),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.qr_code_scanner,
              title: l10n.joinMethodScanTitle,
              description: l10n.joinMethodScanDesc,
              onTap: () => _openQrScanner(context, widgetRef),
            ),
          ],
        ),
      ),
    );
  }

  void _openJoinWithCode(BuildContext context, WidgetRef ref) {
    // Pop back to home, then show join dialog
    Navigator.popUntil(context, (route) => route.isFirst);
    showDialog<Chat>(
      context: context,
      builder: (ctx) => JoinDialog(
        onJoined: (chat) {
          ref.read(myChatsProvider.notifier).refresh();
        },
      ),
    );
  }

  void _openQrScanner(BuildContext context, WidgetRef ref) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code == null || !context.mounted) return;

    final chatService = ref.read(chatServiceProvider);
    final languageCode = ref.read(localeProvider).languageCode;
    final chat = await chatService.getChatByCode(code, languageCode: languageCode);
    if (!context.mounted) return;

    if (chat != null) {
      // Pop back to home, then show join dialog with preloaded chat
      Navigator.popUntil(context, (route) => route.isFirst);
      showDialog<Chat>(
        context: context,
        builder: (ctx) => JoinDialog(
          preloadedChat: chat,
          inviteCode: code,
          onJoined: (joinedChat) {
            ref.read(myChatsProvider.notifier).refresh();
          },
        ),
      );
    } else {
      final l10n = AppLocalizations.of(context);
      context.showInfoSnackBar(l10n.invalidQrCode);
    }
  }
}

/// Selectable card with icon, title, and description.
/// Same visual pattern as the wizard visibility cards.
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
