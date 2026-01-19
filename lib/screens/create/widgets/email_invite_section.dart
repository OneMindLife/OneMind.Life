import 'package:flutter/material.dart';

/// A widget for managing email invites in invite-only mode.
class EmailInviteSection extends StatefulWidget {
  final List<String> emails;
  final void Function(List<String>) onEmailsChanged;

  const EmailInviteSection({
    super.key,
    required this.emails,
    required this.onEmailsChanged,
  });

  @override
  State<EmailInviteSection> createState() => _EmailInviteSectionState();
}

class _EmailInviteSectionState extends State<EmailInviteSection> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _addEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    // Basic email validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    if (widget.emails.contains(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email already added')),
      );
      return;
    }

    widget.onEmailsChanged([...widget.emails, email]);
    _emailController.clear();
  }

  void _removeEmail(String email) {
    widget.onEmailsChanged(widget.emails.where((e) => e != email).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invite by Email',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Only invited email addresses can join this chat',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      hintText: 'user@example.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onFieldSubmitted: (_) => _addEmail(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: _addEmail,
                ),
              ],
            ),
            if (widget.emails.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.emails.map((email) {
                  return Chip(
                    label: Text(email),
                    onDeleted: () => _removeEmail(email),
                  );
                }).toList(),
              ),
            ],
            if (widget.emails.isEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add at least one email to send invites',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
