import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/providers.dart';
import '../../../utils/web_timing_stub.dart'
    if (dart.library.html) '../../../utils/web_timing.dart';

/// Welcome panel — the first screen of the tutorial.
/// On web, the HTML play screen (in index.html) handles all visible UI.
/// This widget manages the handoff between HTML and Flutter, and provides
/// a minimal fallback UI for non-web environments and tests.
class TutorialIntroPanel extends ConsumerStatefulWidget {
  /// Called when user taps play. Passes the hardcoded template key.
  final void Function(String templateKey) onSelect;
  /// Called when auto-advancing from HTML play screen (skip fade-out).
  final void Function(String templateKey)? onHtmlPlay;
  final VoidCallback onSkip;

  const TutorialIntroPanel({
    super.key,
    required this.onSelect,
    this.onHtmlPlay,
    required this.onSkip,
  });

  @override
  ConsumerState<TutorialIntroPanel> createState() => _TutorialIntroPanelState();
}

class _TutorialIntroPanelState extends ConsumerState<TutorialIntroPanel> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).logPlayScreenViewed();

    final htmlCallback = widget.onHtmlPlay ?? widget.onSelect;

    // Case 1: User tapped HTML play BEFORE Flutter loaded
    if (wasHtmlPlayTapped()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) htmlCallback('saturday');
      });
      return;
    }

    // Case 2: Flutter loaded first — register callback so HTML play
    // button can auto-advance when tapped later
    registerHtmlPlayCallback(() {
      if (mounted) htmlCallback('saturday');
    });
  }

  @override
  void dispose() {
    unregisterHtmlPlayCallback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // On web, the HTML play screen (index.html) covers this widget.
    // This minimal UI is only visible in tests and non-web environments.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Play button
            GestureDetector(
              onTap: () {
                ref.read(analyticsServiceProvider).logPlayButtonTapped();
                widget.onSelect('saturday');
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D7377),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('See how it works'),
            const SizedBox(height: 48),

            // Legal text
            _buildAgreementText(context, l10n),

            // Skip button
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onSkip,
              child: const Text('Skip'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgreementText(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${l10n.byContinuingYouAgree} ',
          style: textStyle,
        ),
        GestureDetector(
          onTap: () => context.push('/terms'),
          child: Text(
            l10n.termsOfServiceTitle,
            style: textStyle?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        Text(
          ' ${l10n.andText} ',
          style: textStyle,
        ),
        GestureDetector(
          onTap: () => context.push('/privacy'),
          child: Text(
            l10n.privacyPolicyTitle,
            style: textStyle?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        Text(
          '.',
          style: textStyle,
        ),
      ],
    );
  }
}
