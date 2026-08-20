import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';
import 'name_section.dart';

/// Compact "Welcome, Name" header with pencil icon for inline editing.
/// Placed above the search bar on the home screen.
///
/// Users who haven't named themselves yet (names are no longer
/// auto-generated) see a "Set your name" prompt instead.
class WelcomeHeader extends ConsumerWidget {
  final GlobalKey? widgetKey;

  const WelcomeHeader({super.key, this.widgetKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authDisplayNameProvider);
    final hasName = displayName != null && displayName.isNotEmpty;
    final l10n = AppLocalizations.of(context);

    return Padding(
      key: widgetKey,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              hasName ? l10n.welcomeName(displayName) : l10n.setYourName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: l10n.editName,
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                showNameEditDialog(context, ref, current: displayName),
          ),
        ],
      ),
    );
  }
}
