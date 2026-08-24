import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'basic_info_section.dart';
import 'wizard_common.dart';

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
  // Default ON: the question is pre-filled with "What should we do next?" so the
  // host starts with the evergreen question instead of a blank optional field.
  bool _showMessage = true;

  bool _validate() {
    return widget.formKey.currentState?.validate() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Form(
      key: widget.formKey,
      child: WizardStepLayout(
        icon: Icons.lightbulb_outline,
        title: l10n.wizardStep1Title,
        onContinue: () {
          if (_validate()) {
            widget.onContinue();
          }
        },
        children: [
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
            validator: (v) =>
                v == null || v.trim().isEmpty ? l10n.required : null,
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
    );
  }
}
