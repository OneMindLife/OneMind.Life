import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_colors.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/proposition_content_card.dart';
import '../../widgets/round_winner_item.dart';
import '../rating/read_only_results_screen.dart';

/// Screen showing round-by-round winners for a given cycle (convergence).
/// Tapping a round navigates to that round's full rating results.
class CycleHistoryScreen extends ConsumerStatefulWidget {
  final int cycleId;
  final String convergenceContent;
  final int convergenceNumber;
  final bool showOngoingPlaceholder;

  /// Current leader proposition to show at the bottom during rating phase.
  final Proposition? currentLeader;

  /// Current round number (for the current leader label).
  final int? currentRoundNumber;

  /// Current round ID (for navigating to live results).
  final int? currentRoundId;

  /// All scored propositions for the current round (for results screen).
  final List<Proposition>? currentRoundPropositions;

  const CycleHistoryScreen({
    super.key,
    required this.cycleId,
    required this.convergenceContent,
    required this.convergenceNumber,
    this.showOngoingPlaceholder = false,
    this.currentLeader,
    this.currentRoundNumber,
    this.currentRoundId,
    this.currentRoundPropositions,
  });

  @override
  ConsumerState<CycleHistoryScreen> createState() =>
      _CycleHistoryScreenState();
}

class _CycleHistoryScreenState extends ConsumerState<CycleHistoryScreen> {
  List<Map<String, dynamic>>? _roundData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoundWinners();
  }

  Future<void> _loadRoundWinners() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final languageCode = ref.read(localeProvider).languageCode;
      final data = await chatService.getRoundWinnersForCycle(
        widget.cycleId,
        languageCode: languageCode,
      );
      if (mounted) {
        setState(() {
          _roundData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openRoundResults(Round round) async {
    final propositionService = ref.read(propositionServiceProvider);
    final languageCode = ref.read(localeProvider).languageCode;
    final propositions =
        await propositionService.getPropositionsWithRatings(
          round.id,
          languageCode: languageCode,
        );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReadOnlyResultsScreen(
          propositions: propositions,
          roundNumber: round.customId,
          roundId: round.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.convergenceHistory(widget.convergenceNumber)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildRoundList(theme, l10n),
    );
  }

  Widget _buildRoundList(ThemeData theme, AppLocalizations l10n) {
    // Ascending order: oldest at top, newest at bottom
    final rounds = List<Map<String, dynamic>>.from(_roundData!)
      ..sort((a, b) => (a['round'] as Round).customId.compareTo((b['round'] as Round).customId));
    if (rounds.isEmpty && widget.currentLeader == null) {
      return Center(child: Text(l10n.noPropositionsToDisplay));
    }

    // Determine if the last 2 rounds converged (same winner content)
    bool lastTwoConverged = false;
    if (!widget.showOngoingPlaceholder && rounds.length >= 2) {
      final lastWinners = rounds[rounds.length - 1]['winners'] as List<RoundWinner>;
      final prevWinners = rounds[rounds.length - 2]['winners'] as List<RoundWinner>;
      if (lastWinners.length == 1 && prevWinners.length == 1) {
        lastTwoConverged = lastWinners.first.content == prevWinners.first.content;
      }
    }

    final items = <Widget>[];
    for (var index = 0; index < rounds.length; index++) {
      final round = rounds[index]['round'] as Round;
      final winners = rounds[index]['winners'] as List<RoundWinner>;
      // Blue only if the last 2 rounds have the same sole winner (convergence)
      final isConvergenceWinner = lastTwoConverged &&
          index >= rounds.length - 2;
      final winnerTexts = winners.isNotEmpty
          ? winners.map((w) => w.displayContent ?? '?').toList()
          : ['—'];

      if (index > 0) items.add(const SizedBox(height: 12));
      items.add(RoundWinnerItem(
        winnerTexts: winnerTexts,
        label: winners.length > 1
            ? l10n.roundWinners(round.customId)
            : l10n.roundWinner(round.customId),
        isConvergence: isConvergenceWinner,
        onTap: () => _openRoundResults(round),
      ));
    }

    if (widget.currentLeader != null) {
      items.add(const SizedBox(height: 12));
      items.add(GestureDetector(
        onTap: widget.currentRoundId != null
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReadOnlyResultsScreen(
                      propositions: widget.currentRoundPropositions ?? [],
                      roundNumber: widget.currentRoundNumber ?? 0,
                      roundId: widget.currentRoundId,
                    ),
                  ),
                );
              }
            : null,
        child: UnconstrainedBox(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 64,
            ),
            child: PropositionContentCard(
              content: widget.currentLeader!.displayContent,
              label: l10n.currentLeader,
              borderColor: theme.colorScheme.primary,
              glowColor: theme.colorScheme.primary,
            ),
          ),
        ),
      ));
    } else if (widget.showOngoingPlaceholder) {
      items.add(const SizedBox(height: 12));
      items.add(UnconstrainedBox(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 64,
          ),
          child: PropositionContentCard(
            content: '...',
            label: l10n.chatTourPlaceholderTitle,
            borderColor: AppColors.consensus,
            glowColor: AppColors.consensus,
          ),
        ),
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          children: items,
        ),
      ),
    );
  }
}
