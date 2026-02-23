import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/proposition.dart';
import '../../widgets/rating/rating_model.dart';
import '../../widgets/rating/rating_widget.dart';

/// Read-only screen for viewing previous round results on a grid.
///
/// Displays all propositions positioned by their final MOVDA scores.
/// Only zoom/pan controls are available - no editing.
class ReadOnlyResultsScreen extends StatefulWidget {
  final List<Proposition> propositions;
  final int roundNumber;

  /// Round ID (kept for API compatibility, but not used)
  final int? roundId;

  /// Current user's participant ID (kept for API compatibility, but not used)
  final int? myParticipantId;

  /// Whether to show tutorial hint at the bottom
  final bool showTutorialHint;

  /// Winner name to display in tutorial hint (e.g. "Community Garden won!")
  final String? tutorialWinnerName;

  const ReadOnlyResultsScreen({
    super.key,
    required this.propositions,
    required this.roundNumber,
    this.roundId,
    this.myParticipantId,
    this.showTutorialHint = false,
    this.tutorialWinnerName,
  });

  @override
  State<ReadOnlyResultsScreen> createState() =>
      _ReadOnlyResultsScreenState();
}

class _ReadOnlyResultsScreenState extends State<ReadOnlyResultsScreen> {
  late RatingModel _model;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  void _initializeModel() {
    // Convert propositions to the map format expected by RatingModel
    final propositionMaps = widget.propositions.map((p) => {
      'id': p.id,
      'content': p.displayContent,
      'finalRating': p.finalRating ?? 50.0,
    }).toList();

    _model = RatingModel.fromResults(propositionMaps);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Widget _buildPropositionsGrid() {
    final l10n = AppLocalizations.of(context);

    if (widget.propositions.isEmpty) {
      return Center(
        child: Text(
          l10n.noPropositionsToDisplay,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return RatingWidget(
      propositions: widget.propositions.map((p) => {
        'id': p.id.toString(),
        'content': p.displayContent,
        'position': p.finalRating ?? 50.0,
      }).toList(),
      onRankingComplete: (_) async {
        // No-op for read-only mode
      },
      readOnly: true,
      isResuming: true, // Use isResuming to skip binary phase
    );
  }

  Widget _buildTutorialHint(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Match the tutorial hint styling from tutorial_screen.dart
    final backgroundColor = theme.colorScheme.primaryContainer.withAlpha(100);
    final borderColor = theme.colorScheme.primary.withAlpha(80);
    final contentColor = theme.colorScheme.onPrimaryContainer;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: contentColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.tutorialResultsBackHint(widget.tutorialWinnerName ?? ''),
              style: theme.textTheme.bodySmall?.copyWith(
                color: contentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.roundResults(widget.roundNumber),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.showTutorialHint) _buildTutorialHint(context),
            Expanded(child: _buildPropositionsGrid()),
          ],
        ),
      ),
    );
  }
}
