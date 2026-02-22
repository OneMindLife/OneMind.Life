import 'package:flutter/material.dart';

/// An inline widget that renders a term as a hyperlink-styled tappable text.
/// On tap, shows a compact AlertDialog with the term's definition.
///
/// Use this in static/label text only, never on interactive elements like buttons.
class GlossaryTerm extends StatelessWidget {
  final String term;
  final String definition;
  final TextStyle? style;

  const GlossaryTerm({
    super.key,
    required this.term,
    required this.definition,
    this.style,
  });

  void _showDefinition(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(term),
        content: Text(definition),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? DefaultTextStyle.of(context).style;
    return InkWell(
      onTap: () => _showDefinition(context),
      child: Text(
        term,
        style: defaultStyle.copyWith(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
