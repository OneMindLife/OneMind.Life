import 'package:flutter/material.dart';

/// Shared "How It Works" diagram widget used across landing pages,
/// SEO pages, and blog posts.
class HowItWorksDiagram extends StatelessWidget {
  const HowItWorksDiagram({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'how-it-works-diagram.png',
        fit: BoxFit.contain,
        errorBuilder: (_, e, _) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text(
            'Propose → Rate → Results → Repeat until convergence',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
