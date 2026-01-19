import 'package:flutter/material.dart';
import 'form_inputs.dart';

/// Maximum character limit for chat names.
/// This ensures titles display fully without truncation across all screens.
const int kChatNameMaxLength = 50;

/// Basic info section for chat name, initial message, and description
class BasicInfoSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController messageController;
  final TextEditingController descriptionController;

  const BasicInfoSection({
    super.key,
    required this.nameController,
    required this.messageController,
    required this.descriptionController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Basic Info'),
        const SizedBox(height: 16),
        TextFormField(
          controller: nameController,
          maxLength: kChatNameMaxLength,
          decoration: const InputDecoration(
            labelText: 'Chat Name *',
            hintText: 'e.g., Team Lunch Friday',
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: messageController,
          decoration: const InputDecoration(
            labelText: 'Initial Message *',
            hintText: 'The opening topic or question',
          ),
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description (Optional)',
            hintText: 'Additional context',
          ),
          maxLines: 2,
        ),
      ],
    );
  }
}
