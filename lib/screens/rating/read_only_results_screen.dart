import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/proposition.dart';
import '../../widgets/rating/rating_model.dart';
import '../../widgets/rating/rating_widget.dart';
import '../home_tour/widgets/spotlight_overlay.dart';

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

  /// Optional custom title for the tutorial hint (overrides default)
  final String? tutorialHintTitle;

  /// Optional custom description for the tutorial hint (overrides default)
  final String? tutorialHintDescription;

  /// Callback to exit the tutorial (shows close button in AppBar when set)
  final VoidCallback? onExitTutorial;

  const ReadOnlyResultsScreen({
    super.key,
    required this.propositions,
    required this.roundNumber,
    this.roundId,
    this.myParticipantId,
    this.showTutorialHint = false,
    this.tutorialWinnerName,
    this.tutorialHintTitle,
    this.tutorialHintDescription,
    this.onExitTutorial,
  });

  @override
  State<ReadOnlyResultsScreen> createState() =>
      _ReadOnlyResultsScreenState();
}

class _ReadOnlyResultsScreenState extends State<ReadOnlyResultsScreen> {
  late RatingModel _model;
  bool _dismissedHint = false;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showHint = widget.showTutorialHint && !_dismissedHint;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.roundResults,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (widget.onExitTutorial != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.skip,
              onPressed: widget.onExitTutorial,
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Full-size results grid (no layout shift)
            Positioned.fill(child: _buildPropositionsGrid()),
            // Floating hint overlay
            if (showHint)
              Positioned(
                left: 16,
                right: 16,
                top: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _dismissedHint = true),
                  child: TourTooltipCard(
                    title: widget.tutorialHintTitle ?? l10n.tutorialHintRateIdeas,
                    description: widget.tutorialHintDescription ??
                        l10n.tutorialResultsBackHint(
                            widget.tutorialWinnerName ?? ''),
                    onNext: () => setState(() => _dismissedHint = true),
                    onSkip: widget.onExitTutorial ?? () => Navigator.of(context).pop(),
                    stepIndex: 0,
                    totalSteps: 1,
                    nextLabel: l10n.homeTourFinish,
                    skipLabel: l10n.tutorialSkipMenuItem,
                    stepOfLabel: '',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
