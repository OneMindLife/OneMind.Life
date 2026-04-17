import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_colors.dart';
import '../landing/how_it_works_diagram.dart';
import '../../providers/providers.dart';
import 'blog_data.dart';

/// Renders a single blog post from [BlogPost] data.
class BlogPostScreen extends ConsumerStatefulWidget {
  final BlogPost post;
  const BlogPostScreen({super.key, required this.post});

  @override
  ConsumerState<BlogPostScreen> createState() => _BlogPostScreenState();
}

class _BlogPostScreenState extends ConsumerState<BlogPostScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).logScreenView(
          screenName: 'blog_${widget.post.slug}',
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width > 768;

    return Scaffold(
      body: SelectionArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 64 : 20,
            vertical: 40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back nav
                    TextButton.icon(
                      onPressed: () => context.go('/blog'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('All Articles'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.seed,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Text(
                      widget.post.title,
                      style: (isWide
                              ? theme.textTheme.displaySmall
                              : theme.textTheme.headlineMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Meta line
                    Text(
                      '${widget.post.author}  \u00b7  ${_formatDate(widget.post.date)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Body sections
                    for (final section in widget.post.sections)
                      _buildSection(theme, section),

                    const SizedBox(height: 48),

                    // Footer
                    Center(
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => context.go('/'),
                            child: const Text('Home'),
                          ),
                          TextButton(
                            onPressed: () => context.go('/blog'),
                            child: const Text('Blog'),
                          ),
                          TextButton(
                            onPressed: () => context.go('/privacy'),
                            child: const Text('Privacy'),
                          ),
                          TextButton(
                            onPressed: () => context.go('/terms'),
                            child: const Text('Terms'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme, BlogSection section) {
    return switch (section) {
      BlogParagraph(text: final t) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            t,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.7,
            ),
          ),
        ),
      BlogHeading(text: final t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            t,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      BlogSubheading(text: final t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            t,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.seed,
            ),
          ),
        ),
      BlogBulletList(items: final items) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('\u2022  ',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.seed,
                            fontWeight: FontWeight.bold,
                          )),
                      Expanded(
                        child: Text(
                          item,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      BlogCta(
        text: final t,
        buttonLabel: final label,
        route: final route
      ) =>
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                AppColors.seed.withValues(alpha: 0.08),
                AppColors.consensus.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Column(
            children: [
              Text(
                t,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go(route),
                icon: const Icon(Icons.arrow_forward),
                label: Text(label),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.seed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      BlogDiagram() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: HowItWorksDiagram(),
        ),
      BlogDivider() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(),
        ),
    };
  }

  String _formatDate(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return '${months[month]} $day, ${parts[0]}';
  }
}
