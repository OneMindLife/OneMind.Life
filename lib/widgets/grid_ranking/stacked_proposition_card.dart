import 'dart:async';
import 'package:flutter/material.dart';
import 'grid_ranking_model.dart';
import 'proposition_card.dart';

/// Auto-cycling widget for displaying a stack of propositions at the same position
class StackedPropositionCard extends StatefulWidget {
  final RankingProposition defaultCard;
  final List<RankingProposition> allCardsInStack;
  final bool isActive;
  final GridRankingModel model;

  const StackedPropositionCard({
    super.key,
    required this.defaultCard,
    required this.allCardsInStack,
    required this.isActive,
    required this.model,
  });

  @override
  State<StackedPropositionCard> createState() => _StackedPropositionCardState();
}

class _StackedPropositionCardState extends State<StackedPropositionCard>
    with SingleTickerProviderStateMixin {
  Timer? _cycleTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late RankingProposition _displayedCard;

  @override
  void initState() {
    super.initState();
    _displayedCard = widget.defaultCard;

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation =
        Tween<double>(begin: 1.0, end: 0.0).animate(_fadeController);

    _startAutoCycle();
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StackedPropositionCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.allCardsInStack.length != widget.allCardsInStack.length) {
      _startAutoCycle();
    }

    if (oldWidget.defaultCard.id != widget.defaultCard.id) {
      final positionChanged =
          (oldWidget.defaultCard.position - widget.defaultCard.position).abs() >
              0.01;

      if (widget.defaultCard.isActive &&
          !_displayedCard.isActive &&
          positionChanged) {
        setState(() {
          _displayedCard = widget.defaultCard;
        });
        _fadeController.reset();
        return;
      }

      if (_displayedCard.isActive &&
          !widget.defaultCard.isActive &&
          positionChanged) {
        _fadeController.value = 1.0;
        setState(() {
          _displayedCard = widget.defaultCard;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _fadeController.reverse();
          }
        });
        return;
      }

      _fadeController.forward(from: 0.0).then((_) {
        if (mounted) {
          setState(() {
            _displayedCard = widget.defaultCard;
          });
          _fadeController.reverse();
        }
      });
    }
  }

  void _startAutoCycle() {
    _cycleTimer?.cancel();

    if (widget.allCardsInStack.length > 1) {
      _cycleTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted) {
          widget.model.cycleStackCard(
            widget.defaultCard.position,
            widget.defaultCard.id,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cardContent = PropositionCard(
      proposition: _displayedCard,
      isActive: _displayedCard.isActive,
      activeGlowColor: theme.colorScheme.primary,
    );

    if (widget.allCardsInStack.length > 1) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left arrow
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.model.cyclePreviousStackCard(
                widget.defaultCard.position,
                widget.defaultCard.id,
              );
            },
            child: Icon(
              Icons.chevron_left,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),

          // Card content
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stack indicator badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha:0.3),
                    ),
                  ),
                  child: Text(
                    '${widget.allCardsInStack.length} stacked',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: cardContent,
                ),
              ],
            ),
          ),

          // Right arrow
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.model.cycleStackCard(
                widget.defaultCard.position,
                widget.defaultCard.id,
              );
            },
            child: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
        ],
      );
    } else {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: cardContent,
      );
    }
  }
}
