import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_colors.dart';
import '../../providers/providers.dart';
import 'blog_data.dart';

/// Blog index page listing all published articles.
class BlogIndexScreen extends ConsumerStatefulWidget {
  const BlogIndexScreen({super.key});

  @override
  ConsumerState<BlogIndexScreen> createState() => _BlogIndexScreenState();
}

class _BlogIndexScreenState extends ConsumerState<BlogIndexScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).logScreenView(
          screenName: 'blog_index',
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
                    // Nav
                    TextButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('OneMind'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.seed,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header
                    Text(
                      'OneMind Blog',
                      style: (isWide
                              ? theme.textTheme.displaySmall
                              : theme.textTheme.headlineMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Insights on group decision making, consensus building, '
                      'and team alignment.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Post list
                    for (var i = 0; i < blogPosts.length; i++) ...[
                      if (i > 0) const Divider(height: 48),
                      _PostCard(post: blogPosts[i]),
                    ],

                    if (blogPosts.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(64),
                          child: Text(
                            'Coming soon.',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final BlogPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.go('/blog/${post.slug}'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDate(post.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.seed,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.metaDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              'Read more \u2192',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.seed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
