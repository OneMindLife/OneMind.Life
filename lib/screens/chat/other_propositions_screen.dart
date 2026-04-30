import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/proposition_content_card.dart';

/// Displays all propositions submitted in the current round, newest to
/// oldest. Watches the chat detail provider so new submissions appear
/// live, and uses [Proposition.displayContent] to respect the chat's
/// viewing language.
class OtherPropositionsScreen extends ConsumerWidget {
  final ChatDetailParams params;

  const OtherPropositionsScreen({super.key, required this.params});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stateAsync = ref.watch(chatDetailProvider(params));

    final others = stateAsync.valueOrNull?.propositions
        .where((p) => !p.isCarriedForward && p.participantId != null)
        .toList() ?? [];
    final countText = others.isNotEmpty ? ' (${others.length})' : '';

    return Scaffold(
      appBar: AppBar(title: Text('${l10n.otherPropositionsTitle}$countText')),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.error(e.toString()))),
        data: (state) {
          final others = state.propositions
              .where((p) => !p.isCarriedForward && p.participantId != null)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (others.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.noOtherPropositionsYet,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: others.length,
            separatorBuilder: (_, _) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final prop = others[index];
              return PropositionContentCard(
                content: prop.displayContent,
                borderColor: AppColors.consensus,
                glowColor: AppColors.consensus,
              );
            },
          );
        },
      ),
    );
  }
}
