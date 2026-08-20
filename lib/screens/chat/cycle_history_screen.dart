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
///
/// This screen shows COMPLETED rounds only. We deliberately never show
/// in-progress data for the current round (current leader, scored
/// propositions, etc.) — exposing it would let a user who finished rating
/// share their screen with a user who hasn't, which is a cheating vector.
class CycleHistoryScreen extends ConsumerStatefulWidget {
  final int cycleId;
  final String convergenceContent;
  final int convergenceNumber;
  final bool showOngoingPlaceholder;

  /// How many consecutive round wins lock in a permanent winner for this chat.
  /// 1 = Instant mode (single round), 2 = Convergence mode. Controls both the
  /// screen title (Winner vs Convergence) and which trailing rounds are
  /// highlighted as the locked-in winner.
  final int confirmationRoundsRequired;

  /// Chat's rating mode — forwarded to [ReadOnlyResultsScreen] so a matches
  /// chat's past rounds render the ranked leaderboard, not the 0–100 grid.
  final String ratingMode;

  /// Owning chat id — threaded into the per-winner read-aloud analytics event.
  final int? chatId;

  const CycleHistoryScreen({
    super.key,
    required this.cycleId,
    required this.convergenceContent,
    required this.convergenceNumber,
    this.showOngoingPlaceholder = false,
    this.confirmationRoundsRequired = 2,
    this.ratingMode = 'grid',
    this.chatId,
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
    final results = await Future.wait([
      propositionService.getPropositionsWithRatings(
        round.id,
        languageCode: languageCode,
      ),
      propositionService.getRaterCount(round.id),
    ]);
    final propositions = results[0] as List<Proposition>;
    final raterCount = results[1] as int;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReadOnlyResultsScreen(
          propositions: propositions,
          roundNumber: round.customId,
          roundId: round.id,
          ratingMode: widget.ratingMode,
          raterCount: raterCount,
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
        title: Text(widget.confirmationRoundsRequired == 1
            ? l10n.winnerHistory(widget.convergenceNumber)
            : l10n.convergenceHistory(widget.convergenceNumber)),
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
    if (rounds.isEmpty && !widget.showOngoingPlaceholder) {
      return Center(child: Text(l10n.noPropositionsToDisplay));
    }

    // Highlight the trailing rounds that locked in the winner. For a completed
    // cycle that's the last `confirmationRoundsRequired` rounds, provided they
    // share the same sole winner. Instant mode (1) highlights the final round;
    // Convergence mode (2) highlights the final two matching rounds. A tie
    // breaks the run, so it won't be counted.
    int convergedRounds = 0;
    if (!widget.showOngoingPlaceholder && rounds.isNotEmpty) {
      final need = widget.confirmationRoundsRequired;
      String? winnerContent;
      for (var i = rounds.length - 1; i >= 0 && convergedRounds < need; i--) {
        final w = rounds[i]['winners'] as List<RoundWinner>;
        if (w.length != 1) break;
        if (winnerContent == null) {
          winnerContent = w.first.content;
        } else if (w.first.content != winnerContent) {
          break;
        }
        convergedRounds++;
      }
      if (convergedRounds < need) convergedRounds = 0;
    }

    final items = <Widget>[];
    for (var index = 0; index < rounds.length; index++) {
      final round = rounds[index]['round'] as Round;
      final winners = rounds[index]['winners'] as List<RoundWinner>;
      // Blue for the trailing locked-in run (size depends on the chat's mode).
      final isConvergenceWinner =
          convergedRounds > 0 && index >= rounds.length - convergedRounds;
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
        showTts: true,
        chatId: widget.chatId?.toString(),
        cycleId: widget.cycleId,
      ));
    }

    if (widget.showOngoingPlaceholder) {
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
