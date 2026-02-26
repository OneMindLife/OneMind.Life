import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Section header used on the home screen (e.g. "PENDING REQUESTS", "YOUR CHATS").
///
/// Uses labelSmall, uppercase, w600, letterSpacing 0.8 — intentionally distinct
/// from [SectionHeader] in create/widgets/form_inputs.dart which uses titleMedium/bold
/// for form wizard context.
class HomeSectionHeader extends StatelessWidget {
  final String title;

  const HomeSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }
}
