import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'basic_info_section.dart';

/// Step 1 of the create chat wizard: The Question
/// Focuses purely on chat name and initial message/question.
class WizardStepQuestion extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController messageController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onContinue;

  const WizardStepQuestion({
    super.key,
    required this.nameController,
    required this.messageController,
    required this.formKey,
    required this.onContinue,
  });

  bool _validate() {
    return formKey.currentState?.validate() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Large icon as visual anchor
                    Icon(
                      Icons.lightbulb_outline,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      l10n.wizardStep1Title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      l10n.wizardStep1Subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Chat name field
                    TextFormField(
                      controller: nameController,
                      maxLength: kChatNameMaxLength,
                      decoration: InputDecoration(
                        labelText: l10n.chatNameRequired,
                        hintText: l10n.chatNameHint,
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? l10n.required : null,
                    ),
                    const SizedBox(height: 16),

                    // Initial message field (optional)
                    TextFormField(
                      controller: messageController,
                      decoration: InputDecoration(
                        labelText: l10n.initialMessageOptional,
                        hintText: l10n.initialMessageHint,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (_validate()) {
                  onContinue();
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.continue_),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
