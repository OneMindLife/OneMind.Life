import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../l10n/generated/app_localizations.dart';

/// Card showing a pending join request with an amber left border.
///
/// Accepts primitive fields so it can be used in both the real home screen
/// (with [onCancel]) and the home tour (with [onCancel] = null to hide the button).
class PendingRequestCard extends StatelessWidget {
  final String chatName;
  final String? subtitle;
  final VoidCallback? onCancel;

  const PendingRequestCard({
    super.key,
    required this.chatName,
    this.subtitle,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semanticLabel =
        '${l10n.pending} request for $chatName. ${l10n.waitingForHostApproval}';

    return Semantics(
      label: semanticLabel,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Warm amber left border — needs attention
              ExcludeSemantics(
                child: Container(
                  width: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.consensus,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    chatName,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              l10n.waitingForHostApproval,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (onCancel != null) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: l10n.cancelRequest,
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: l10n.cancelRequest,
                            onPressed: onCancel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
