import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/invite_service.dart';
import '../../utils/language_utils.dart';
import '../../widgets/error_view.dart';

/// Screen that handles joining via invite token or code from URL
class InviteJoinScreen extends ConsumerStatefulWidget {
  /// Invite token from URL (e.g., /join/invite?token=xxx)
  final String? token;

  /// Invite code from URL (e.g., /join/ABC123)
  final String? code;

  const InviteJoinScreen({
    super.key,
    this.token,
    this.code,
  });

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  bool _isLoading = true;
  bool _isJoining = false;
  String? _error;

  // Token-based invite data
  InviteTokenResult? _inviteResult;

  // Code-based lookup data
  Chat? _foundChat;

  // Personal code flag — when true, join via redeem_personal_code
  bool _isPersonalCode = false;

  @override
  void initState() {
    super.initState();
    // Defer initialization to after the frame is built to allow context access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeInvite();
    });
  }

  Future<void> _initializeInvite() async {
    if (widget.token != null) {
      await _validateToken();
    } else if (widget.code != null) {
      await _lookupByCode();
    } else {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.noTokenOrCode;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _validateToken() async {
    try {
      final inviteService = ref.read(inviteServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final result = await inviteService.validateInviteToken(widget.token!);

      if (result == null || !result.isValid) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _error = l10n.invalidExpiredInvite;
            _isLoading = false;
          });
        }
        return;
      }

      // Check if user is already a participant in this chat
      final existingParticipant = await participantService.getMyParticipant(result.chatId);

      if (existingParticipant != null && existingParticipant.status == ParticipantStatus.active) {
        // User is already in this chat - go to home
        if (mounted) {
          context.go('/');
        }
        return;
      }

      setState(() {
        _inviteResult = result;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.failedToValidateInvite;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _lookupByCode() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final chat = await chatService.getChatByCode(widget.code!);

      if (chat == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _error = l10n.chatNotFound;
            _isLoading = false;
          });
        }
        return;
      }

      // Check if user is already a participant in this chat
      final existingParticipant = await participantService.getMyParticipant(chat.id);

      if (existingParticipant != null && existingParticipant.status == ParticipantStatus.active) {
        // User is already in this chat - go to home
        if (mounted) {
          context.go('/');
        }
        return;
      }

      // Personal code chats: set flag for direct redemption
      if (chat.accessMethod == AccessMethod.personalCode) {
        setState(() {
          _foundChat = chat;
          _isPersonalCode = true;
          _isLoading = false;
        });
        return;
      }

      // For invite-only chats accessed via code URL, redirect to home
      // since they need to enter their email to validate access
      final inviteOnly = await inviteService.isInviteOnly(chat.id);
      if (inviteOnly) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _error = l10n.inviteOnlyError;
            _isLoading = false;
          });
        }
        return;
      }

      setState(() {
        _foundChat = chat;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.failedToLookupChat;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _joinChat() async {
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final name = authService.displayName!;

      // Get chat ID
      final chatId = _inviteResult?.chatId ?? _foundChat?.id;
      if (chatId == null) {
        setState(() {
          _error = l10n.chatNotFound;
          _isJoining = false;
        });
        return;
      }

      // Get the invite token (only set for token-based invites)
      final inviteToken = widget.token;

      // Personal code: redeem directly, no approval
      if (_isPersonalCode && widget.code != null) {
        final personalCodeService = ref.read(personalCodeServiceProvider);
        final result = await personalCodeService.redeemCode(
          code: widget.code!,
          displayName: name,
        );

        // Refresh chat list
        ref.read(myChatsProvider.notifier).refresh();

        // Log analytics
        final joinedChatId = result['chat_id'] as int;
        ref.read(analyticsServiceProvider).logChatJoined(
          chatId: joinedChatId.toString(),
          joinMethod: 'personal_code',
        );

        if (mounted) {
          // Land on Home with ?chat_id=N so HomeScreen auto-opens the chat
          // the user just joined (HomeScreen._handleReturnToChat handles it).
          context.go('/?chat_id=$joinedChatId');
        }
        return;
      }

      final requireApproval =
          _inviteResult?.requireApproval ?? _foundChat?.requireApproval ?? false;

      if (requireApproval) {
        // Request to join (requires host approval)
        await participantService.requestToJoin(
          chatId: chatId,
          displayName: name,
        );

        if (mounted) {
          context.showInfoSnackBar(l10n.joinRequestSent);
          context.go('/');
        }
      } else {
        // Join directly
        final participant = await participantService.joinChat(
          chatId: chatId,
          displayName: name,
          isHost: false,
        );

        // Accept the invite if we have a token
        if (inviteToken != null) {
          await inviteService.acceptInvite(
            inviteToken: inviteToken,
            participantId: participant.id,
          );
        }

        // Refresh chat list
        ref.read(myChatsProvider.notifier).refresh();

        // Log analytics event
        final joinMethod = widget.token != null ? 'deep_link' : 'invite_code';
        ref.read(analyticsServiceProvider).logChatJoined(
          chatId: chatId.toString(),
          joinMethod: joinMethod,
        );

        if (mounted) {
          // Land on Home with ?chat_id=N so HomeScreen auto-opens the chat
          // the user just joined (HomeScreen._handleReturnToChat handles it).
          context.go('/?chat_id=$chatId');
        }
      }
    } catch (e) {
      setState(() {
        _error = l10n.failedToJoinChat(e.toString());
        _isJoining = false;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.joinScreenTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _inviteResult == null && _foundChat == null
              ? _buildErrorState()
              : _buildJoinForm(),
    );
  }

  Widget _buildErrorState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.invalidInviteTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? l10n.invalidInviteDefault,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/'),
              child: Text(l10n.goHome),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinForm() {
    final l10n = AppLocalizations.of(context)!;
    final chatName = _inviteResult?.chatName ?? _foundChat?.name ?? 'Chat';
    final chatMessage = _inviteResult?.chatInitialMessage ??
        _foundChat?.initialMessage ??
        '';
    final hostDisplayName = _foundChat?.hostDisplayName;
    final requireApproval = _isPersonalCode
        ? false
        : _inviteResult?.requireApproval ?? _foundChat?.requireApproval ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chat info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.invitedToJoin,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              chatName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (hostDisplayName != null &&
                                hostDisplayName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                l10n.hostedBy(hostDisplayName),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.translate,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  LanguageUtils.shortLabel(
                                    _inviteResult?.translationLanguages ??
                                        _foundChat?.translationLanguages ??
                                        const ['en'],
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (chatMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      chatMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Approval notice
          if (requireApproval) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.tertiary),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.requiresApprovalNotice,
                      style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Error message
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],

          const SizedBox(height: 24),

          // Join button
          FilledButton(
            onPressed: _isJoining ? null : _joinChat,
            child: _isJoining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(requireApproval ? l10n.requestToJoinButton : l10n.joinChatButton),
          ),

          const SizedBox(height: 12),

          // Cancel button
          TextButton(
            onPressed: _isJoining ? null : () => context.go('/'),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}
