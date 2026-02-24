import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';

/// Compact "Welcome, Name" header with pencil icon for inline editing.
/// Placed above the search bar on the home screen.
class WelcomeHeader extends ConsumerWidget {
  final GlobalKey? widgetKey;

  const WelcomeHeader({super.key, this.widgetKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authDisplayNameProvider) ?? '';
    final l10n = AppLocalizations.of(context);

    return Padding(
      key: widgetKey,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.welcomeName(displayName),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: l10n.editName,
            visualDensity: VisualDensity.compact,
            onPressed: () => _showEditDialog(context, ref, displayName),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, String currentName) {
    final controller = TextEditingController(text: currentName);
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: l10n.enterYourName,
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) {
              _saveName(ref, name);
              Navigator.pop(dialogContext);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _saveName(ref, name);
                Navigator.pop(dialogContext);
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _saveName(WidgetRef ref, String name) {
    ref.read(authServiceProvider).setDisplayName(name);
    // Invalidate the display name provider so the UI rebuilds
    ref.invalidate(authDisplayNameProvider);
  }
}
