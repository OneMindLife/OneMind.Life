import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'form_inputs.dart';

/// Maximum character limit for chat names.
/// This ensures titles display fully without truncation across all screens.
const int kChatNameMaxLength = 50;

/// Basic info section for chat name and optional initial message
class BasicInfoSection extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController messageController;

  const BasicInfoSection({
    super.key,
    required this.nameController,
    required this.messageController,
  });

  @override
  State<BasicInfoSection> createState() => _BasicInfoSectionState();
}

class _BasicInfoSectionState extends State<BasicInfoSection> {
  bool _showMessage = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.basicInfo),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.nameController,
          maxLength: kChatNameMaxLength,
          decoration: InputDecoration(
            labelText: l10n.chatNameRequired,
            hintText: l10n.chatNameHint,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.setFirstMessage),
          value: _showMessage,
          onChanged: (v) {
            setState(() => _showMessage = v);
            if (!v) widget.messageController.clear();
          },
        ),
        if (_showMessage) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.messageController,
            decoration: InputDecoration(
              labelText: l10n.initialMessageOptional,
              hintText: l10n.initialMessageHint,
              helperText: l10n.initialMessageHelperText,
            ),
            maxLines: 3,
          ),
        ],
      ],
    );
  }
}
