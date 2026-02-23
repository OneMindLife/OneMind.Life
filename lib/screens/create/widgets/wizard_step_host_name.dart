import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'form_inputs.dart';

/// Final step of the create chat wizard: Host name.
/// Only shown when the user hasn't set a display name yet.
/// Explains that the name is shown to participants joining the chat.
class WizardStepHostName extends StatelessWidget {
  final TextEditingController hostNameController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final bool isLoading;

  const WizardStepHostName({
    super.key,
    required this.hostNameController,
    required this.formKey,
    required this.onBack,
    required this.onCreate,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.wizardOneLastThing,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SettingTile(
                      question: "What's your name?",
                      description:
                          'Shown to people who join so they know who created it',
                      child: TextFormField(
                        controller: hostNameController,
                        decoration: InputDecoration(
                          hintText: l10n.enterYourName,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.pleaseEnterYourName;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLoading ? null : onBack,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.arrow_back, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.back),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            if (formKey.currentState?.validate() ?? false) {
                              onCreate();
                            }
                          },
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(l10n.createChat),
                              const SizedBox(width: 8),
                              const Icon(Icons.rocket_launch, size: 18),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
