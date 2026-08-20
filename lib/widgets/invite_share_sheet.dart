import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_colors.dart';
import '../config/env_config.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';

/// Conversion-focused share dialog for the quick-create flow.
///
/// Unlike [QrCodeShareDialog] (link + QR + manual code, for in-person), this is
/// built to get the host to actually SEND the link to others:
///   * leads with the "why" + "no account needed" (kills the host's hesitation),
///   * a big primary "Share link" button (native share sheet) as the main action,
///   * the link below as a tap-to-copy fallback,
///   * no QR / no raw code — single clear focus.
///
/// English-only by design (matches the rest of the quick-create flow).
class InviteShareSheet extends ConsumerStatefulWidget {
  const InviteShareSheet({
    super.key,
    required this.chatName,
    required this.inviteCode,
    required this.chatId,
    this.auto = false,
  });

  final String chatName;
  final String inviteCode;
  final String chatId;

  /// True when the sheet auto-opened on chat load (vs. user-invoked from the
  /// app bar / result screen). Threaded into the `invite_dialog_shown` event.
  final bool auto;

  static Future<void> show(
    BuildContext context, {
    required String chatName,
    required String inviteCode,
    required String chatId,
    bool auto = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => InviteShareSheet(
        chatName: chatName,
        inviteCode: inviteCode,
        chatId: chatId,
        auto: auto,
      ),
    );
  }

  @override
  ConsumerState<InviteShareSheet> createState() => _InviteShareSheetState();
}

class _InviteShareSheetState extends ConsumerState<InviteShareSheet> {
  // Captured in initState so dispose() never has to touch ref (the provider
  // container is alive while the dialog is up, but this keeps teardown safe).
  late final AnalyticsService _analytics;

  // Flips true once the host actually shares/copies, so the dismissal event
  // can distinguish "closed after sharing" from a cold walk-away.
  bool _hadShared = false;

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(analyticsServiceProvider);
    _analytics.logInviteDialogShown(chatId: widget.chatId, auto: widget.auto);
  }

  @override
  void dispose() {
    // Fires on every close path — X button, title close, barrier tap, back
    // gesture — because the dialog only lives while shown. had_shared lets
    // analysis filter to true rejections (had_shared == false).
    _analytics.logInviteDialogDismissed(
      chatId: widget.chatId,
      hadShared: _hadShared,
    );
    super.dispose();
  }

  String get _url => '${EnvConfig.webAppUrl}/join/${widget.inviteCode}';

  // Native share sheet. Logs the intent ('share_sheet'); falls back to copying
  // the link if the platform has no share sheet (no extra event on fallback).
  Future<void> _share(BuildContext context) async {
    _hadShared = true;
    _analytics.logInviteShared(chatId: widget.chatId, shareMethod: 'share_sheet');
    try {
      await Share.share(
        'Rank these with me: ${widget.chatName}\n$_url',
        subject: widget.chatName,
      );
    } catch (_) {
      if (context.mounted) await _copyToClipboard(context);
    }
  }

  // Direct tap-to-copy. Logs 'copy' — the cold-funnel signal that was
  // previously invisible (the dialog fired no analytics at all).
  Future<void> _copy(BuildContext context) async {
    _hadShared = true;
    _analytics.logInviteShared(chatId: widget.chatId, shareMethod: 'copy');
    await _copyToClipboard(context);
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Invite your group')),
          IconButton(
            icon: const Icon(Icons.close),
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The "why" + the objection-killer.
          Text(
            'Send this link to your group. They rank the options and you\'ll '
            'see the winner here when everyone\'s done — no account needed.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),

          // Primary action: native share sheet.
          FilledButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.share),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Share link'),
            ),
          ),
          const SizedBox(height: 12),

          // Tap-to-copy link (fallback).
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _copy(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Divider with "or scan" — for inviting people in the same room.
          Row(
            children: [
              Expanded(child: Divider(color: cs.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or scan',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Expanded(child: Divider(color: cs.outlineVariant)),
            ],
          ),
          const SizedBox(height: 16),

          // QR code pointing at the same join link.
          Center(
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
                  data: _url,
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
        ],
        ),
      ),
      actionsPadding: EdgeInsets.zero,
    );
  }
}
