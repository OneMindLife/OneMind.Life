import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// Bottom sheet shown when the FAB is tapped.
/// Shows 3 actions: Create Chat, Join Chat, Discover Chats.
/// Tapping Join Chat splits it into two buttons (Enter Code / Scan QR)
/// in the same row, with a back arrow to collapse.
class FabActionSheet extends StatefulWidget {
  final VoidCallback onCreateChat;
  final VoidCallback onJoinWithCode;
  final VoidCallback onScanQrCode;
  final VoidCallback onDiscoverChats;

  const FabActionSheet({
    super.key,
    required this.onCreateChat,
    required this.onJoinWithCode,
    required this.onScanQrCode,
    required this.onDiscoverChats,
  });

  /// Show the action sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onCreateChat,
    required VoidCallback onJoinWithCode,
    required VoidCallback onScanQrCode,
    required VoidCallback onDiscoverChats,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => FabActionSheet(
        onCreateChat: () {
          Navigator.pop(ctx);
          onCreateChat();
        },
        onJoinWithCode: () {
          Navigator.pop(ctx);
          onJoinWithCode();
        },
        onScanQrCode: () {
          Navigator.pop(ctx);
          onScanQrCode();
        },
        onDiscoverChats: () {
          Navigator.pop(ctx);
          onDiscoverChats();
        },
      ),
    );
  }

  @override
  State<FabActionSheet> createState() => _FabActionSheetState();
}

class _FabActionSheetState extends State<FabActionSheet> {
  bool _joinExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Create Chat
            _ActionTile(
              icon: Icons.add_comment,
              label: l10n.createChat,
              onTap: widget.onCreateChat,
            ),
            const SizedBox(height: 4),

            // Join Chat — collapses/expands inline
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _joinExpanded
                  ? Row(
                      key: const ValueKey('join-expanded'),
                      children: [
                        // Back arrow
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () =>
                              setState(() => _joinExpanded = false),
                          tooltip: l10n.back,
                        ),
                        const SizedBox(width: 4),
                        // Enter Code
                        Expanded(
                          child: _CompactActionTile(
                            icon: Icons.keyboard,
                            label: l10n.joinWithCode,
                            onTap: widget.onJoinWithCode,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Scan QR
                        Expanded(
                          child: _CompactActionTile(
                            icon: Icons.qr_code_scanner,
                            label: l10n.scanQrCode,
                            onTap: widget.onScanQrCode,
                          ),
                        ),
                      ],
                    )
                  : _ActionTile(
                      key: const ValueKey('join-collapsed'),
                      icon: Icons.group_add,
                      label: l10n.joinChat,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => _joinExpanded = true),
                    ),
            ),
            const SizedBox(height: 4),

            // Discover Chats
            _ActionTile(
              icon: Icons.explore,
              label: l10n.discoverChats,
              onTap: widget.onDiscoverChats,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width action tile with leading icon container + label.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

/// Compact tile for the split join row — icon on top, label below.
class _CompactActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CompactActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colorScheme.onPrimaryContainer, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
