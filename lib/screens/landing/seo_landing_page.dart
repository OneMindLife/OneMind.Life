import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../config/app_colors.dart';
import 'how_it_works_diagram.dart';
import '../../providers/providers.dart';

/// Data model for an SEO-optimized keyword landing page.
class SeoPageData {
  /// URL slug (e.g., "decision-making-tool").
  final String slug;

  // Hero
  final String heroHeadline;
  final String heroSubheadline;
  final String ctaLabel;

  // Problem / pain point
  final String problemHeadline;
  final String problemDescription;

  // Solution steps (how OneMind solves it)
  final List<SeoStep> steps;

  // Feature highlights
  final List<SeoFeature> features;

  // Social proof line
  final String proofLine;

  // Closing CTA
  final String closingHeadline;
  final String closingSubheadline;

  const SeoPageData({
    required this.slug,
    required this.heroHeadline,
    required this.heroSubheadline,
    required this.ctaLabel,
    required this.problemHeadline,
    required this.problemDescription,
    required this.steps,
    required this.features,
    required this.proofLine,
    required this.closingHeadline,
    required this.closingSubheadline,
  });
}

class SeoStep {
  final IconData icon;
  final String title;
  final String description;
  const SeoStep({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class SeoFeature {
  final IconData icon;
  final String title;
  final String description;
  const SeoFeature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// Reusable SEO landing page template.
///
/// Each keyword page uses the same structure but different copy
/// optimized for its target keyword cluster.
class SeoLandingPage extends ConsumerStatefulWidget {
  final SeoPageData data;
  const SeoLandingPage({super.key, required this.data});

  @override
  ConsumerState<SeoLandingPage> createState() => _SeoLandingPageState();
}

class _SeoLandingPageState extends ConsumerState<SeoLandingPage> {
  YoutubePlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).logScreenView(
          screenName: 'seo_${widget.data.slug}',
        );
  }

  @override
  void dispose() {
    _videoController?.close();
    super.dispose();
  }

  void _onCtaPressed() {
    ref.read(analyticsServiceProvider).logLandingCtaClicked(
          variant: 'seo_${widget.data.slug}',
        );
    context.go('/tutorial');
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
            _buildHero(theme, isWide),
            _buildProblem(theme, isWide, contentWidth),
            _buildSteps(theme, isWide, contentWidth),
            _buildFeatures(theme, isWide, contentWidth),
            _buildVideo(theme, contentWidth),
            _buildClosingCta(theme),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  // ── Hero ──
  Widget _buildHero(ThemeData theme, bool isWide) {
    final d = widget.data;
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
              // Nav back to home
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('OneMind'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.seed,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                d.heroHeadline,
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
              Text(
                d.heroSubheadline,
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
              FilledButton.icon(
                onPressed: _onCtaPressed,
                icon: const Icon(Icons.arrow_forward),
                label: Text(d.ctaLabel),
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
                'Free \u2022 No account required',
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

  // ── Problem Statement ──
  Widget _buildProblem(ThemeData theme, bool isWide, double contentWidth) {
    final d = widget.data;
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth * 0.8),
          child: Column(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 40, color: AppColors.consensus),
              const SizedBox(height: 16),
              Text(
                d.problemHeadline,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                d.problemDescription,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── How It Works Steps ──
  Widget _buildSteps(ThemeData theme, bool isWide, double contentWidth) {
    final steps = widget.data.steps;
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: 56,
      ),
      color: colorScheme.surfaceContainerLow,
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
              const SizedBox(height: 40),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(width: 24),
                      Expanded(
                          child: _buildStepCard(theme, steps[i], i + 1)),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _buildStepCard(theme, steps[i], i + 1),
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

  Widget _buildStepCard(ThemeData theme, SeoStep step, int number) {
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
              'Step $number',
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

  // ── Features ──
  Widget _buildFeatures(ThemeData theme, bool isWide, double contentWidth) {
    final features = widget.data.features;
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            children: [
              Text(
                'Why Teams Choose OneMind',
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
                    for (var i = 0; i < features.length; i++) ...[
                      if (i > 0) const SizedBox(width: 32),
                      Expanded(
                          child: _buildFeatureTile(theme, features[i])),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < features.length; i++) ...[
                      if (i > 0) const SizedBox(height: 24),
                      _buildFeatureTile(theme, features[i]),
                    ],
                  ],
                ),
              const SizedBox(height: 32),
              // Social proof
              Text(
                widget.data.proofLine,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile(ThemeData theme, SeoFeature feature) {
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Icon(feature.icon, size: 40, color: AppColors.consensus),
        const SizedBox(height: 16),
        Text(
          feature.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          feature.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Video ──
  Widget _buildVideo(ThemeData theme, double contentWidth) {
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
      color: colorScheme.surfaceContainerLow,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth * 0.85),
          child: Column(
            children: [
              Text(
                'See It in Action',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: YoutubePlayer(
                  controller: _videoController ??= YoutubePlayerController
                      .fromVideoId(
                    videoId: 'YKqNCg3Oj9k',
                    params: const YoutubePlayerParams(
                      showFullscreenButton: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Closing CTA ──
  Widget _buildClosingCta(ThemeData theme) {
    final d = widget.data;
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
                d.closingHeadline,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                d.closingSubheadline,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _onCtaPressed,
                icon: const Icon(Icons.arrow_forward),
                label: Text(d.ctaLabel),
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

  // ── Footer ──
  Widget _buildFooter(ThemeData theme) {
    final colorScheme = theme.colorScheme;
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
                color: colorScheme.outline,
              ),
            ),
            _link('Privacy Policy', '/privacy'),
            _link('Terms of Service', '/terms'),
            _link('Home', '/'),
          ],
        ),
      ),
    );
  }

  Widget _link(String label, String path) {
    return InkWell(
      onTap: () => context.go(path),
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
