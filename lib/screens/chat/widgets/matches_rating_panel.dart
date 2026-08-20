import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/proposition.dart';
import '../../../providers/providers.dart';
import '../../../services/matches/match_pair_selector.dart';
import '../../../widgets/proposition_content_card.dart';
import '../../../widgets/tts_button.dart';

/// Inline pairwise ("matches") rating UI — lives in the chat bottom panel
/// during the rating phase (no separate full-screen grid). Shows two
/// propositions; the user taps the better one, marks them Equal, or Skips.
///
/// State is local: prior votes are fetched once, then tracked in memory as the
/// user votes (each submit also persists to pairwise_comparisons). The
/// [MatchPairSelector] picks the next pair, enforcing the equal-exposure
/// invariant. See docs/MATCHES_RATING_MODE_SPEC.md §5.
class MatchesRatingPanel extends ConsumerStatefulWidget {
  const MatchesRatingPanel({
    super.key,
    required this.roundId,
    required this.participantId,
    required this.rateable,
    required this.objective,
    required this.onSkip,
    required this.onDone,
    this.onVote,
    this.accentColor,
  });

  /// Optional accent for the option cards (border/fill). Defaults to the
  /// rating color; the C15 tree passes orange so duel cards match its
  /// proposition-card language.
  final Color? accentColor;

  /// Propositions the user may rate — caller MUST exclude the user's own.
  final List<Proposition> rateable;
  final int roundId;
  final int participantId;
  final MatchObjective objective;

  /// Skip the rating phase (same semantics as the grid's skip). Null when the
  /// chat disallows skipping rating (or skip is otherwise unavailable) — the
  /// Skip button is hidden entirely in that case, mirroring grid mode.
  final VoidCallback? onSkip;

  /// No useful pair remains — the user has finished rating this round.
  final VoidCallback onDone;

  /// Fired after every judgment that persisted (vote, tie, or pair skip) —
  /// lets the host UI refresh anything derived from the round's comparisons
  /// (e.g. the tree section's live standings).
  final VoidCallback? onVote;

  @override
  ConsumerState<MatchesRatingPanel> createState() => _MatchesRatingPanelState();
}

class _MatchesRatingPanelState extends ConsumerState<MatchesRatingPanel> {
  final _selector = MatchPairSelector();
  List<PriorVote> _priorVotes = [];
  MatchPair? _current;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final votes = await ref.read(propositionServiceProvider).getPriorPairwiseVotes(
            roundId: widget.roundId,
            participantId: widget.participantId,
          );
      _priorVotes = votes;
    } catch (_) {
      // Non-fatal: start from no prior votes.
      _priorVotes = [];
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _advance();
    });
  }

  /// Recompute the next pair from current state; fire onDone if exhausted.
  void _advance() {
    _current = _selector.nextPair(
      rateable: widget.rateable,
      priorVotes: _priorVotes,
      objective: widget.objective,
    );
    if (_current == null) {
      // Defer so we don't call back synchronously during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone();
      });
    }
  }

  Future<void> _vote(int winnerId, int loserId, {bool isTie = false}) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(propositionServiceProvider).submitPairwiseComparison(
            roundId: widget.roundId,
            participantId: widget.participantId,
            winnerPropositionId: winnerId,
            loserPropositionId: loserId,
            isTie: isTie,
          );
      _priorVotes = [
        ..._priorVotes,
        PriorVote(winnerId: winnerId, loserId: loserId, isTie: isTie),
      ];
      widget.onVote?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).couldNotSaveChoice)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _advance();
        });
      }
    }
  }

  /// "Done" leaves the rating phase entirely — confirm first so a stray tap
  /// doesn't end the user's rating for the round.
  Future<void> _confirmDone() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.doneRatingQuestion),
        content: Text(l10n.doneRatingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onSkip?.call();
    }
  }

  /// Skip THIS pair only (not the whole phase): record it so the selector
  /// won't show it again (and both ideas' exposure counts go up), then move on.
  Future<void> _skipPair(int propAId, int propBId) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(propositionServiceProvider).submitPairwiseSkip(
            roundId: widget.roundId,
            participantId: widget.participantId,
            propAId: propAId,
            propBId: propBId,
          );
      _priorVotes = [
        ..._priorVotes,
        PriorVote(
            winnerId: propAId, loserId: propBId, isTie: false, isSkip: true),
      ];
      widget.onVote?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotSkip)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _advance();
        });
      }
    }
  }

  /// Shared bordered, icon-above-label pill used for Equal / Skip / Done so the
  /// three controls are visually consistent (same border, icon placement, size).
  Widget _judgmentPill({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) {
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: Size.zero,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  /// Per-match counter so a rater sees movement on every tap (the round's
  /// participation bar only flips at completion, which feels static when solo).
  /// We show a bare count, NOT "X of N": the selector's equal-exposure invariant
  /// terminates full_rank early and by a path-dependent amount (e.g. 5 options →
  /// 6 matches not 10; 6 options → 7 or 12), so there is no honest total to show.
  Widget _matchProgress(ThemeData theme) {
    return Center(
      child: Text(
          AppLocalizations.of(context).matchNumber(_priorVotes.length + 1),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final l10n = AppLocalizations.of(context);
    final pair = _current;
    if (pair == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(l10n.doneWaitingForRound,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      );
    }

    final theme = Theme.of(context);
    return AbsorbPointer(
      absorbing: _submitting,
      child: Opacity(
        opacity: _submitting ? 0.6 : 1.0,
        child: Padding(
          // Horizontal breathing room so cards don't touch the screen edges
          // (matches the chat screen's content insets).
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(l10n.whichIsBetterTapOne,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 8),
            _matchProgress(theme),
            const SizedBox(height: 10),
            // Always stacked (vertical): top option, "Equal" framed by thin
            // rules, then bottom option. Constrained + centred so the cards
            // don't stretch awkwardly wide on a desktop browser. (Side-by-side
            // looked cramped, so we never go horizontal regardless of width.)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OptionCard(
                      proposition: pair.top,
                      accentColor: widget.accentColor,
                      onTap: () => _vote(pair.top.id, pair.bottom.id),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.outlineVariant,
                            endIndent: 10,
                          ),
                        ),
                        _judgmentPill(
                          theme: theme,
                          icon: Icons.balance,
                          label: l10n.equal,
                          onPressed: () =>
                              _vote(pair.top.id, pair.bottom.id, isTie: true),
                        ),
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.outlineVariant,
                            indent: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _OptionCard(
                      proposition: pair.bottom,
                      accentColor: widget.accentColor,
                      onTap: () => _vote(pair.bottom.id, pair.top.id),
                    ),
                  ],
                ),
              ),
            ),
            // Skip (pass this match) + Done (leave the phase) — same bordered,
            // icon-above-label pill style as Equal for consistency. Shown only
            // when the chat allows skipping.
            if (widget.onSkip != null) ...[
              const SizedBox(height: 14),
              Center(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _judgmentPill(
                      key: const Key('matches-skip-pair'),
                      theme: theme,
                      icon: Icons.skip_next,
                      label: l10n.skip,
                      onPressed: _submitting
                          ? null
                          : () => _skipPair(pair.top.id, pair.bottom.id),
                    ),
                    _judgmentPill(
                      key: const Key('matches-done'),
                      theme: theme,
                      icon: Icons.check,
                      label: l10n.done,
                      onPressed: _confirmDone,
                    ),
                  ],
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.proposition,
    required this.onTap,
    this.accentColor,
  });
  final Proposition proposition;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: PropositionContentCard(
        content: proposition.displayContent,
        // Speak-aloud (TTS) button on each voting option — accessibility, so
        // raters can hear each option read aloud during voting.
        trailing: TtsButton(
          text: proposition.displayContent,
          source: 'rating_option',
        ),
        // Light fill + stronger border so each option reads as a *pressable
        // button*, not a label — first-time raters didn't realise the two
        // cards are tappable. Mirrors the /try demo's affordance (the demo
        // proved the clearer treatment; the real chat inherits it).
        // Accent callers (C15 tree) want outline-only; the default rating
        // look keeps its light fill.
        backgroundColor: accentColor == null
            ? AppColors.rating.withValues(alpha: 0.07)
            : null,
        borderColor: (accentColor ?? AppColors.rating).withValues(alpha: 0.8),
        borderWidth: 1.5,
      ),
    );
  }
}
