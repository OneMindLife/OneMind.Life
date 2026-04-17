import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'basic_info_section.dart';
import 'form_inputs.dart';

/// Step 1 of the create chat wizard: The Question
/// Focuses purely on chat name and optional initial message/question.
class WizardStepQuestion extends StatefulWidget {
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

  @override
  State<WizardStepQuestion> createState() => _WizardStepQuestionState();
}

class _WizardStepQuestionState extends State<WizardStepQuestion> {
  late bool _showMessage = widget.messageController.text.isNotEmpty;

  bool _validate() {
    return widget.formKey.currentState?.validate() ?? false;
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
                key: widget.formKey,
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
                    const SizedBox(height: 24),

                    // Chat name field
                    TextFormField(
                      controller: widget.nameController,
                      maxLength: kChatNameMaxLength,
                      decoration: InputDecoration(
                        labelText: l10n.chatName,
                        hintText: l10n.chatNameHint,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? l10n.required
                          : null,
                    ),
                    const SizedBox(height: 8),

                    // Toggle for initial message
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.setFirstMessage),
                      value: _showMessage,
                      onChanged: (v) {
                        setState(() => _showMessage = v);
                        if (!v) widget.messageController.clear();
                      },
                    ),

                    // Initial message field (shown when toggled on)
                    if (_showMessage) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: widget.messageController,
                        decoration: InputDecoration(
                          labelText: l10n.initialMessageLabel,
                          hintText: l10n.initialMessageHint,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
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
                  widget.onContinue();
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
