import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/round.dart';
import '../../../widgets/chat_dashboard_card.dart';
import '../models/home_tour_state.dart';

/// A static mock of the home screen content with fake data.
/// Progressively reveals widgets as the tour advances.
/// Each section has a GlobalKey so the parent can measure positions
/// and animate the tooltip overlay.
class MockHomeContent extends StatelessWidget {
  final HomeTourStep currentStep;
  final GlobalKey welcomeHeaderKey;
  final GlobalKey searchBarKey;
  final GlobalKey yourChatsKey;
  final GlobalKey pendingRequestKey;

  const MockHomeContent({
    super.key,
    required this.currentStep,
    required this.welcomeHeaderKey,
    required this.searchBarKey,
    required this.yourChatsKey,
    required this.pendingRequestKey,
  });

  bool _isRevealed(HomeTourStep step) {
    return step.index <= currentStep.index;
  }

  double _opacity(HomeTourStep step) {
    // For non-body steps, all cards at uniform opacity
    // (parent handles overall dimming via outer AnimatedOpacity)
    if (currentStep == HomeTourStep.languageSelector ||
        currentStep == HomeTourStep.tutorialButton ||
        currentStep == HomeTourStep.createFab ||
        currentStep == HomeTourStep.menu ||
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
          // --- Welcome Header (step 0) ---
          if (_isRevealed(HomeTourStep.welcomeName)) ...[
            AnimatedOpacity(
              key: welcomeHeaderKey,
              opacity: _opacity(HomeTourStep.welcomeName),
              duration: const Duration(milliseconds: 250),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.welcomeName('Brave Fox'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // --- Search Bar (step 2) ---
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
                  ChatDashboardCard(
                    name: l10n.appTitle,
                    initialMessage: 'What topic should we discuss next?',
                    onTap: () {},
                    participantCount: 12,
                    phase: RoundPhase.proposing,
                    translationLanguages: const ['en', 'es'],
                  ),
                  const SizedBox(height: 8),
                  ChatDashboardCard(
                    name: 'Weekend Plans',
                    initialMessage: 'What should we do this Saturday?',
                    onTap: () {},
                    participantCount: 4,
                    phase: RoundPhase.rating,
                    translationLanguages: const ['en'],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // --- Pending Requests (after Your Chats) ---
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
                  _MockPendingCard(
                    chatName: 'Book Club',
                    subtitle: 'What should we read next?',
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
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }
}

class _MockPendingCard extends StatelessWidget {
  final String chatName;
  final String subtitle;

  const _MockPendingCard({
    required this.chatName,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: AppColors.consensus,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chatName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
            ),
          ],
        ),
      ),
    );
  }
}

