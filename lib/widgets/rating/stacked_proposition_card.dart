import 'package:flutter/material.dart';
import 'rating_model.dart';
import 'proposition_card.dart';

/// Widget for displaying a stack of propositions at the same position.
/// User cycles through cards with left/right arrows.
class StackedPropositionCard extends StatefulWidget {
  final RatingProposition defaultCard;
  final List<RatingProposition> allCardsInStack;
  final bool isActive;
  final RatingModel model;

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
  int _currentIndex = 0;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _currentIndex = _findIndex(widget.defaultCard.id);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StackedPropositionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.defaultCard.id != oldWidget.defaultCard.id) {
      final newIndex = _findIndex(widget.defaultCard.id);
      if (newIndex != _currentIndex) {
        _cycleTo(newIndex);
      }
    } else if (_currentIndex >= widget.allCardsInStack.length) {
      _currentIndex = 0;
    }
  }

  int _findIndex(String id) {
    final idx = widget.allCardsInStack.indexWhere((c) => c.id == id);
    return idx >= 0 ? idx : 0;
  }

  RatingProposition get _currentCard =>
      widget.allCardsInStack[_currentIndex];

  void _cycleTo(int newIndex) {
    if (_fadeController.isAnimating) {
      _fadeController.stop();
    }
    _fadeController.reverse().then((_) {
      if (mounted) {
        setState(() => _currentIndex = newIndex);
        _fadeController.forward();
      }
    });
  }

  void _cycleNext() {
    _cycleTo((_currentIndex + 1) % widget.allCardsInStack.length);
  }

  void _cyclePrevious() {
    _cycleTo(
      (_currentIndex - 1 + widget.allCardsInStack.length) %
          widget.allCardsInStack.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _currentCard;

    Widget cardContent = PropositionCard(
      proposition: card,
      isActive: widget.isActive || card.isActive,
      activeGlowColor: theme.colorScheme.primary,
    );

    if (widget.allCardsInStack.length > 1) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cyclePrevious,
            child: Icon(
              Icons.chevron_left,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          Flexible(
            child: FadeTransition(
              opacity: _fadeController,
              child: cardContent,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cycleNext,
            child: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
        ],
      );
    } else {
      return cardContent;
    }
  }
}
