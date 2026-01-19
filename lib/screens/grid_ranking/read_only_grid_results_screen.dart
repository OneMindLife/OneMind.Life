import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/proposition.dart';
import '../../widgets/grid_ranking/grid_ranking_model.dart';
import '../../widgets/grid_ranking/grid_ranking_widget.dart';

/// Read-only screen for viewing previous round results on a grid.
///
/// Displays all propositions from a round positioned by their final MOVDA scores.
/// Only zoom/pan controls are available - no editing.
class ReadOnlyGridResultsScreen extends StatefulWidget {
  final List<Proposition> propositions;
  final int roundNumber;

  const ReadOnlyGridResultsScreen({
    super.key,
    required this.propositions,
    required this.roundNumber,
  });

  @override
  State<ReadOnlyGridResultsScreen> createState() =>
      _ReadOnlyGridResultsScreenState();
}

class _ReadOnlyGridResultsScreenState extends State<ReadOnlyGridResultsScreen> {
  late GridRankingModel _model;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  void _initializeModel() {
    // Convert propositions to the map format expected by GridRankingModel
    final propositionMaps = widget.propositions.map((p) => {
      'id': p.id,
      'content': p.displayContent,
      'finalRating': p.finalRating ?? 50.0,
    }).toList();

    _model = GridRankingModel.fromResults(propositionMaps);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
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
        child: widget.propositions.isEmpty
            ? Center(
                child: Text(
                  l10n.noPropositionsToDisplay,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            : GridRankingWidget(
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
              ),
      ),
    );
  }
}
