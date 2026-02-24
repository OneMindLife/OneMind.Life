import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/home_tour_state.dart';

/// A static mock of the home screen content with fake data.
/// Progressively reveals widgets as the tour advances.
/// Each section has a GlobalKey so the parent can measure positions
/// and animate the tooltip overlay.
class MockHomeContent extends StatelessWidget {
  final HomeTourStep currentStep;
  final GlobalKey searchBarKey;
  final GlobalKey pendingRequestKey;
  final GlobalKey yourChatsKey;

  const MockHomeContent({
    super.key,
    required this.currentStep,
    required this.searchBarKey,
    required this.pendingRequestKey,
    required this.yourChatsKey,
  });

  bool _isRevealed(HomeTourStep step) {
    return step.index <= currentStep.index;
  }

  double _opacity(HomeTourStep step) {
    // For non-body steps, all cards at uniform opacity
    // (parent handles overall dimming via outer AnimatedOpacity)
    if (currentStep == HomeTourStep.exploreButton ||
        currentStep == HomeTourStep.createFab ||
        currentStep == HomeTourStep.howItWorks ||
        currentStep == HomeTourStep.legalDocs ||
        currentStep == HomeTourStep.complete) {
      return 1.0;
    }
    // For body card steps, only the active card is bright
    if (step == currentStep) return 1.0;
    return 0.25;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Search Bar (step 0) ---
          if (_isRevealed(HomeTourStep.searchBar)) ...[
            AnimatedOpacity(
              key: searchBarKey,
              opacity: _opacity(HomeTourStep.searchBar),
              duration: const Duration(milliseconds: 250),
              child: TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: l10n.searchYourChatsOrJoinWithCode,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // --- Pending Requests (step 2) ---
          if (_isRevealed(HomeTourStep.pendingRequest)) ...[
            AnimatedOpacity(
              key: pendingRequestKey,
              opacity: _opacity(HomeTourStep.pendingRequest),
              duration: const Duration(milliseconds: 250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(context, l10n.pendingRequests),
                  const SizedBox(height: 8),
                  const _MockPendingCard(chatName: 'Book Club'),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // --- Your Chats (step 3) ---
          if (_isRevealed(HomeTourStep.yourChats)) ...[
            AnimatedOpacity(
              key: yourChatsKey,
              opacity: _opacity(HomeTourStep.yourChats),
              duration: const Duration(milliseconds: 250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(context, l10n.yourChats),
                  const SizedBox(height: 8),
                  _MockChatCard(
                    name: l10n.appTitle,
                    subtitle: '...',
                    icon: Icons.public,
                    isOfficial: true,
                  ),
                  const SizedBox(height: 8),
                  const _MockChatCard(
                    name: 'Weekend Plans',
                    subtitle: 'What should we do this Saturday?',
                    icon: Icons.chat_bubble_outline,
                    isOfficial: false,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

/// Mock chat card that mirrors the real _ChatCard visual structure
class _MockChatCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData icon;
  final bool isOfficial;

  const _MockChatCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.isOfficial,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isOfficial
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isOfficial
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Mock pending request card that mirrors the real _PendingRequestCard
class _MockPendingCard extends StatelessWidget {
  final String chatName;

  const _MockPendingCard({
    required this.chatName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.hourglass_empty,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 16),
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.pending,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onTertiary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
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
          ],
        ),
      ),
    );
  }
}
