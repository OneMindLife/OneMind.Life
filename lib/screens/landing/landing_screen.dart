import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../config/app_colors.dart';
import '../../providers/providers.dart';
// NOTE: AppColors.seed and AppColors.consensus are brand colors and kept as-is.
// Only text/surface/border colors are replaced with theme-aware equivalents.
import '../../services/analytics_service.dart';
import '../../services/ab_test_service.dart';
import 'how_it_works_diagram.dart';
import 'landing_content.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  late final LandingVariant _variant;
  late final LandingCopy _copy;
  late final AnalyticsService _analytics;
  YoutubePlayerController? _videoController;

  /// Track which sections have already been logged to avoid duplicates
  final Set<String> _viewedSections = {};

  /// Track which scroll depth thresholds have been logged
  final Set<int> _loggedDepths = {};

  /// Section keys for tracking (in order of appearance)
  static const _sectionKeys = [
    'hero',
    'how_it_works',
    'benefits',
    'video',
    'closing_cta',
    'footer',
  ];

  @override
  void initState() {
    super.initState();
    final abService = ref.read(abTestServiceProvider);
    _variant = abService.getVariant();
    _copy = getCopy(_variant);
    _analytics = ref.read(analyticsServiceProvider);

    // Track variant as user property + log landing view
    _analytics.setUserProperty(
      name: 'landing_variant',
      value: _variant.name,
    );
    _analytics.logLandingViewed(variant: _variant.name);
  }

  @override
  void dispose() {
    _videoController?.close();
    super.dispose();
  }

  void _onCtaPressed() {
    _analytics.logLandingCtaClicked(variant: _variant.name);
    context.go('/tutorial');
  }

  void _onSectionVisible(String section) {
    if (_viewedSections.contains(section)) return;
    _viewedSections.add(section);
    _analytics.logLandingSectionViewed(
      section: section,
      variant: _variant.name,
    );

    // Calculate scroll depth based on which sections have been seen
    final sectionIndex = _sectionKeys.indexOf(section);
    if (sectionIndex < 0) return;
    final percent =
        (((sectionIndex + 1) / _sectionKeys.length) * 100).round();
    // Log at standard thresholds: 25, 50, 75, 100
    for (final threshold in [25, 50, 75, 100]) {
      if (percent >= threshold && !_loggedDepths.contains(threshold)) {
        _loggedDepths.add(threshold);
        _analytics.logLandingScrollDepth(
          percent: threshold,
          variant: _variant.name,
        );
      }
    }
  }

  Widget _tracked(String sectionKey, Widget child) {
    return VisibilityDetector(
      key: Key('landing_$sectionKey'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.3) {
          _onSectionVisible(sectionKey);
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth > 768;
    final contentWidth = isWide ? 900.0 : screenWidth;

    return Scaffold(
      body: SelectionArea(
        child: ListView(
          children: [
            // ── Hero Section ──
            _tracked(
              'hero',
              _HeroSection(
                copy: _copy,
                isWide: isWide,
                onCtaPressed: _onCtaPressed,
              ),
            ),

            // ── How It Works ──
            _tracked(
              'how_it_works',
              _HowItWorksSection(isWide: isWide, contentWidth: contentWidth),
            ),

            // ── Benefits ──
            _tracked(
              'benefits',
              _BenefitsSection(
                copy: _copy,
                isWide: isWide,
                contentWidth: contentWidth,
              ),
            ),

            // ── Video Section ──
            _tracked(
              'video',
              _VideoSection(
                contentWidth: contentWidth,
                onControllerCreated: (c) => _videoController = c,
              ),
            ),

            // ── Closing CTA ──
            _tracked(
              'closing_cta',
              _ClosingSection(
                copy: _copy,
                onCtaPressed: _onCtaPressed,
              ),
            ),

            // ── Footer ──
            _tracked('footer', _Footer(theme: theme)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Hero Section
// =============================================================================

class _HeroSection extends StatelessWidget {
  final LandingCopy copy;
  final bool isWide;
  final VoidCallback onCtaPressed;

  const _HeroSection({
    required this.copy,
    required this.isWide,
    required this.onCtaPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: isWide ? 80 : 48,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.seed.withValues(alpha: 0.05),
            AppColors.consensus.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // Logo
              Icon(
                Icons.psychology,
                size: 64,
                color: AppColors.seed,
              ),
              const SizedBox(height: 24),

              // Headline
              Text(
                copy.headline,
                style: (isWide
                        ? theme.textTheme.displaySmall
                        : theme.textTheme.headlineMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Subheadline
              Text(
                copy.subheadline,
                style: (isWide
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // CTA Button
              FilledButton.icon(
                onPressed: onCtaPressed,
                icon: const Icon(Icons.arrow_forward),
                label: Text(copy.ctaLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.seed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No account required',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// How It Works Section
// =============================================================================

class _HowItWorksSection extends StatelessWidget {
  final bool isWide;
  final double contentWidth;

  const _HowItWorksSection({
    required this.isWide,
    required this.contentWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const steps = [
      _StepData(
        icon: Icons.lightbulb_outline,
        number: '1',
        title: 'Propose',
        description: 'Everyone submits ideas anonymously. '
            'No bias, no groupthink — just honest contributions.',
      ),
      _StepData(
        icon: Icons.star_outline,
        number: '2',
        title: 'Rate',
        description: 'The group rates every idea on a simple scale. '
            'Fair, transparent, and impossible to manipulate.',
      ),
      _StepData(
        icon: Icons.emoji_events_outlined,
        number: '3',
        title: 'Converge',
        description: 'When the same idea wins multiple rounds, '
            'that\'s convergence — the group\'s true answer.',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            children: [
              Text(
                'How It Works',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Three simple steps to real consensus',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(width: 24),
                      Expanded(child: _StepCard(step: steps[i])),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _StepCard(step: steps[i]),
                    ],
                  ],
                ),
              const SizedBox(height: 40),
              const HowItWorksDiagram(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepData {
  final IconData icon;
  final String number;
  final String title;
  final String description;

  const _StepData({
    required this.icon,
    required this.number,
    required this.title,
    required this.description,
  });
}

class _StepCard extends StatelessWidget {
  final _StepData step;

  const _StepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.seed.withValues(alpha: 0.1),
              child: Icon(step.icon, color: AppColors.seed, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Step ${step.number}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.seed,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              step.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Benefits Section
// =============================================================================

class _BenefitsSection extends StatelessWidget {
  final LandingCopy copy;
  final bool isWide;
  final double contentWidth;

  const _BenefitsSection({
    required this.copy,
    required this.isWide,
    required this.contentWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final benefits = [
      (Icons.visibility_off_outlined, copy.benefit1Title, copy.benefit1Desc),
      (Icons.schedule_outlined, copy.benefit2Title, copy.benefit2Desc),
      (Icons.verified_outlined, copy.benefit3Title, copy.benefit3Desc),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: 64,
      ),
      color: colorScheme.surfaceContainerLow,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            children: [
              Text(
                'Why OneMind?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 40),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < benefits.length; i++) ...[
                      if (i > 0) const SizedBox(width: 24),
                      Expanded(
                        child: _BenefitTile(
                          icon: benefits[i].$1,
                          title: benefits[i].$2,
                          description: benefits[i].$3,
                        ),
                      ),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < benefits.length; i++) ...[
                      if (i > 0) const SizedBox(height: 24),
                      _BenefitTile(
                        icon: benefits[i].$1,
                        title: benefits[i].$2,
                        description: benefits[i].$3,
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Icon(icon, size: 40, color: AppColors.consensus),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// =============================================================================
// Video Section
// =============================================================================

class _VideoSection extends StatefulWidget {
  final double contentWidth;
  final ValueChanged<YoutubePlayerController> onControllerCreated;

  const _VideoSection({
    required this.contentWidth,
    required this.onControllerCreated,
  });

  @override
  State<_VideoSection> createState() => _VideoSectionState();
}

class _VideoSectionState extends State<_VideoSection> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: 'YKqNCg3Oj9k',
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
      ),
    );
    widget.onControllerCreated(_controller);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.contentWidth * 0.85),
          child: Column(
            children: [
              Text(
                'See It in Action',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: YoutubePlayer(controller: _controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Closing CTA Section
// =============================================================================

class _ClosingSection extends StatelessWidget {
  final LandingCopy copy;
  final VoidCallback onCtaPressed;

  const _ClosingSection({
    required this.copy,
    required this.onCtaPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.seed.withValues(alpha: 0.08),
            AppColors.consensus.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Text(
                copy.closingHeadline,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                copy.closingSubheadline,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onCtaPressed,
                icon: const Icon(Icons.arrow_forward),
                label: Text(copy.ctaLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.seed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Footer
// =============================================================================

class _Footer extends StatelessWidget {
  final ThemeData theme;

  const _Footer({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            Text(
              '\u00a9 ${DateTime.now().year} OneMind.Life LLC',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            _FooterLink(
              label: 'Privacy Policy',
              onTap: () => context.go('/privacy'),
            ),
            _FooterLink(
              label: 'Terms of Service',
              onTap: () => context.go('/terms'),
            ),
            _FooterLink(
              label: 'Demo',
              onTap: () => context.go('/demo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.seed,
              ),
        ),
      ),
    );
  }
}
