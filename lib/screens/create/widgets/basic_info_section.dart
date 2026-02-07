import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'form_inputs.dart';

/// Maximum character limit for chat names.
/// This ensures titles display fully without truncation across all screens.
const int kChatNameMaxLength = 50;

/// Basic info section for chat name and initial message
class BasicInfoSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController messageController;

  const BasicInfoSection({
    super.key,
    required this.nameController,
    required this.messageController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.basicInfo),
        const SizedBox(height: 16),
        TextFormField(
          controller: nameController,
          maxLength: kChatNameMaxLength,
          decoration: InputDecoration(
            labelText: l10n.chatNameRequired,
            hintText: l10n.chatNameHint,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: messageController,
          decoration: InputDecoration(
            labelText: l10n.initialMessageRequired,
            hintText: l10n.initialMessageHint,
            helperText: l10n.initialMessageHelperText,
          ),
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
        ),
      ],
    );
  }
}
