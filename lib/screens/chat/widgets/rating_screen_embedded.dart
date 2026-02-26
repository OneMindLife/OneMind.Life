import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../../widgets/error_view.dart';

/// An embedded rating screen widget for rating propositions.
/// Note: This is the legacy inline rating screen. The primary rating UI
/// is now RatingScreen for a better UX.
class RatingScreenEmbedded extends ConsumerStatefulWidget {
  final Round round;
  final Participant participant;
  final List<Proposition> propositions;
  final VoidCallback onComplete;

  const RatingScreenEmbedded({
    super.key,
    required this.round,
    required this.participant,
    required this.propositions,
    required this.onComplete,
  });

  @override
  ConsumerState<RatingScreenEmbedded> createState() => _RatingScreenEmbeddedState();
}

class _RatingScreenEmbeddedState extends ConsumerState<RatingScreenEmbedded> {
  late Map<int, int> _ratings;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _ratings = {
      for (var p in widget.propositions) p.id: 50,
    };
  }

  Future<void> _submitRatings() async {
    setState(() => _isSubmitting = true);

    try {
      final propositionService = ref.read(propositionServiceProvider);
      await propositionService.submitRatings(
        propositionIds: widget.propositions.map((p) => p.id).toList(),
        ratings: widget.propositions.map((p) => _ratings[p.id]!).toList(),
        participantId: widget.participant.id,
      );
      widget.onComplete();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() => _isSubmitting = false);
        context.showErrorMessage(l10n.failedToSubmitRatings(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ratePropositions),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.propositions.length,
              itemBuilder: (context, index) {
                final proposition = widget.propositions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          proposition.displayContent,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('0'),
                            Expanded(
                              child: Slider(
                                value: _ratings[proposition.id]!.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 100,
                                label: '${_ratings[proposition.id]}',
                                onChanged: (v) {
                                  setState(() {
                                    _ratings[proposition.id] = v.round();
                                  });
                                },
                              ),
                            ),
                            const Text('100'),
                          ],
                        ),
                        Center(
                          child: Text(
                            '${_ratings[proposition.id]}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRatings,
              child: _isSubmitting
                  ? const CircularProgressIndicator()
                  : Text(l10n.submitRatings),
            ),
          ),
        ],
      ),
    );
  }
}
