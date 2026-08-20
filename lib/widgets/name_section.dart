import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';

/// Max display-name length, matching the wedge's name gate.
const int kDisplayNameMaxLength = 40;

/// Shared identity gate for join/create actions.
///
/// Names are never auto-generated: a user has no display name until they
/// type one here. Two states, keyed off the auth display name:
///  * no name yet — an inline "What's your name?" field. The surrounding
///    screen owns [controller], keeps its primary action disabled while the
///    field is empty (listen to the controller), and calls
///    [commitNameSection] before acting.
///  * has a name — "[asLabel]" (e.g. "Joining as Joel") with a pencil that
///    opens the shared edit dialog, so every join/create moment doubles as
///    the discoverable place to change your name.
class NameSection extends ConsumerWidget {
  final TextEditingController controller;

  /// Builds the has-a-name line, e.g. `(name) => l10n.joiningAs(name)`.
  final String Function(String name) asLabel;

  const NameSection({
    super.key,
    required this.controller,
    required this.asLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = ref.watch(authDisplayNameProvider);

    if (name == null || name.isEmpty) {
      return TextField(
        key: const Key('name-section-field'),
        controller: controller,
        maxLength: kDisplayNameMaxLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: l10n.whatsYourName,
          hintText: l10n.enterYourName,
          helperText: l10n.nameShownToOthers,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            asLabel(name),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          key: const Key('name-section-edit'),
          icon: const Icon(Icons.edit, size: 18),
          tooltip: l10n.editName,
          visualDensity: VisualDensity.compact,
          onPressed: () => showNameEditDialog(context, ref, current: name),
        ),
      ],
    );
  }
}

/// Resolves the display name for an action guarded by a [NameSection]:
/// returns the stored name when one exists, otherwise saves the typed one.
/// Returns null when a name is still required (field empty) — the caller
/// should abort (its button should already be disabled in that state).
Future<String?> commitNameSection(
  WidgetRef ref,
  TextEditingController controller,
) async {
  final auth = ref.read(authServiceProvider);
  if (auth.hasDisplayName) return auth.displayName!;
  final name = controller.text.trim();
  if (name.isEmpty) return null;
  await auth.setDisplayName(name);
  ref.invalidate(authDisplayNameProvider);
  return name;
}

/// Shared "Edit name" dialog (same UX as the home-screen pencil).
/// Returns true when a name was saved.
Future<bool> showNameEditDialog(
  BuildContext context,
  WidgetRef ref, {
  String? current,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: current ?? '');

  Future<void> save(BuildContext dialogContext, String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return;
    Navigator.pop(dialogContext, name);
  }

  final saved = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(current == null || current.isEmpty
          ? l10n.whatsYourName
          : l10n.editName),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: kDisplayNameMaxLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: l10n.enterYourName,
          helperText: l10n.nameShownToOthers,
          counterText: '',
        ),
        onSubmitted: (value) => save(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => save(dialogContext, controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );

  if (saved == null) return false;
  await ref.read(authServiceProvider).setDisplayName(saved);
  ref.invalidate(authDisplayNameProvider);
  return true;
}

/// For tap-to-act flows with no inline form surface (e.g. joining from a
/// Discover card): returns the stored display name, or prompts for one via
/// the shared dialog. Null means the user cancelled — abort the action.
Future<String?> ensureDisplayNameInteractive(
  BuildContext context,
  WidgetRef ref,
) async {
  final auth = ref.read(authServiceProvider);
  if (auth.hasDisplayName) return auth.displayName!;
  final saved = await showNameEditDialog(context, ref);
  if (!saved) return null;
  return auth.displayName;
}
