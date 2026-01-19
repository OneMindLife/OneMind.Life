import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class JoinDialog extends ConsumerStatefulWidget {
  final void Function(Chat chat) onJoined;

  const JoinDialog({super.key, required this.onJoined});

  @override
  ConsumerState<JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<JoinDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  Chat? _foundChat;
  bool _needsName = false;
  bool _isInviteOnly = false;
  String? _validatedInviteToken;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
  }

  void _loadDisplayName() {
    // Read display name from auth service (stored in user metadata)
    final authService = ref.read(authServiceProvider);
    final name = authService.displayName;
    if (name != null && name.isNotEmpty) {
      _nameController.text = name;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _lookupChat() async {
    final l10n = AppLocalizations.of(context);
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = l10n.pleaseEnterSixCharCode);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chatService = ref.read(chatServiceProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final languageCode = ref.read(localeProvider).languageCode;
      final chat = await chatService.getChatByCode(code, languageCode: languageCode);

      if (chat == null) {
        setState(() {
          _error = l10n.chatNotFound;
          _isLoading = false;
        });
        return;
      }

      final authService = ref.read(authServiceProvider);
      final hasName = authService.displayName?.isNotEmpty ?? false;
      final inviteOnly = await inviteService.isInviteOnly(chat.id);

      setState(() {
        _foundChat = chat;
        _needsName = !hasName;
        _isInviteOnly = inviteOnly;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = l10n.failedToLookupChat;
        _isLoading = false;
      });
    }
  }

  Future<void> _validateEmail() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = l10n.pleaseEnterEmailAddress);
      return;
    }

    // Basic email validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = l10n.pleaseEnterValidEmail);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final inviteService = ref.read(inviteServiceProvider);
      final token = await inviteService.validateInviteByEmail(
        chatId: _foundChat!.id,
        email: email,
      );

      if (token == null) {
        setState(() {
          _error = l10n.noInviteFoundForEmail;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _validatedInviteToken = token;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = l10n.failedToValidateInvite;
        _isLoading = false;
      });
    }
  }

  Future<void> _joinChat() async {
    final l10n = AppLocalizations.of(context);
    if (_foundChat == null) return;

    // For invite-only chats, require validated invite
    if (_isInviteOnly && _validatedInviteToken == null) {
      setState(() => _error = l10n.pleaseVerifyEmailFirst);
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.pleaseEnterYourName);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final inviteService = ref.read(inviteServiceProvider);

      // Save display name to auth metadata
      await authService.setDisplayName(name);

      if (_foundChat!.requireApproval) {
        // Request to join (auth.uid() is used automatically)
        await participantService.requestToJoin(
          chatId: _foundChat!.id,
          displayName: name,
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.joinRequestSent),
            ),
          );
        }
      } else {
        // Join directly (auth.uid() is used automatically)
        final participant = await participantService.joinChat(
          chatId: _foundChat!.id,
          displayName: name,
          isHost: false,
        );

        // For invite-only chats, mark the invite as accepted
        if (_isInviteOnly && _validatedInviteToken != null) {
          await inviteService.acceptInvite(
            inviteToken: _validatedInviteToken!,
            participantId: participant.id,
          );
        }

        if (mounted) {
          Navigator.pop(context);
          widget.onJoined(_foundChat!);
        }
      }
    } catch (e) {
      setState(() {
        _error = l10n.failedToJoinChat(e.toString());
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_foundChat == null ? l10n.joinChat : _foundChat!.displayName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_foundChat == null) ...[
              Text(l10n.enterInviteCode),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  UpperCaseTextFormatter(),
                ],
                decoration: InputDecoration(
                  hintText: l10n.inviteCodeHint,
                  counterText: '',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                onSubmitted: (_) => _lookupChat(),
              ),
            ] else ...[
              // Show host name if available
              if (_foundChat!.hostDisplayName != null &&
                  _foundChat!.hostDisplayName!.isNotEmpty) ...[
                Text(
                  l10n.hostedBy(_foundChat!.hostDisplayName!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _foundChat!.displayInitialMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              // Invite-only: require email verification first
              if (_isInviteOnly && _validatedInviteToken == null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.thisChatsRequiresInvite,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.enterEmailForInvite),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: l10n.yourEmailHint,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _validateEmail(),
                ),
              ] else ...[
                // Email verified or not invite-only: show name input
                if (_isInviteOnly && _validatedInviteToken != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.emailVerified(_emailController.text),
                            style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_needsName) ...[
                  Text(l10n.enterDisplayName),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: l10n.yourName,
                    ),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _joinChat(),
                  ),
                ],
              ],
              if (_foundChat!.requireApproval)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.hostApprovalRequired,
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        if (_foundChat == null)
          ElevatedButton(
            onPressed: _isLoading ? null : _lookupChat,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.findChat),
          )
        else if (_isInviteOnly && _validatedInviteToken == null)
          // Invite-only: need to verify email first
          ElevatedButton(
            onPressed: _isLoading ? null : _validateEmail,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.verifyEmail),
          )
        else
          ElevatedButton(
            onPressed: _isLoading ? null : _joinChat,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_foundChat!.requireApproval ? l10n.requestToJoin : l10n.join),
          ),
      ],
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
