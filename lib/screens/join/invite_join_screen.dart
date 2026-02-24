import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/invite_service.dart';
import '../../utils/language_utils.dart';
import '../chat/chat_screen.dart';

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
  final _nameController = TextEditingController();
  bool _isLoading = true;
  bool _isJoining = false;
  String? _error;
  bool _needsName = true;

  // Token-based invite data
  InviteTokenResult? _inviteResult;

  // Code-based lookup data
  Chat? _foundChat;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
    // Defer initialization to after the frame is built to allow context access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeInvite();
    });
  }

  void _loadDisplayName() {
    final authService = ref.read(authServiceProvider);
    final name = authService.displayName;
    if (name != null && name.isNotEmpty) {
      _nameController.text = name;
      _needsName = false;
    }
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
      final chatService = ref.read(chatServiceProvider);
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
        // User is already in this chat - redirect to home then push chat
        final chat = await chatService.getChatById(result.chatId);
        if (mounted && chat != null) {
          // Go to home first, then push chat on top (so back button works)
          context.go('/');
          // Wait for home to mount, then push chat
          await Future.delayed(const Duration(milliseconds: 100));
          rootNavigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(chat: chat),
            ),
          );
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
        // User is already in this chat - redirect to home then push chat
        if (mounted) {
          // Go to home first, then push chat on top (so back button works)
          context.go('/');
          // Wait for home to mount, then push chat
          await Future.delayed(const Duration(milliseconds: 100));
          rootNavigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(chat: chat),
            ),
          );
        }
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.pleaseEnterYourName);
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final chatService = ref.read(chatServiceProvider);

      // Save display name to auth metadata
      await authService.setDisplayName(name);

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

      final requireApproval =
          _inviteResult?.requireApproval ?? _foundChat?.requireApproval ?? false;

      if (requireApproval) {
        // Request to join (requires host approval)
        await participantService.requestToJoin(
          chatId: chatId,
          displayName: name,
        );

        // Track that user requested to join this chat
        // Used to navigate directly to chat after tutorial if approved
        ref.read(pendingJoinChatIdProvider.notifier).state = chatId;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.joinRequestSent),
            ),
          );
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

        // Get full chat object for navigation
        final chat = _foundChat ?? await chatService.getChatById(chatId);

        if (mounted && chat != null) {
          // Navigate to chat
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(chat: chat),
            ),
          );
        } else if (mounted) {
          // Fallback: go home
          context.go('/');
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
    _nameController.dispose();
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
                    color: AppColors.textSecondary,
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
    final requireApproval =
        _inviteResult?.requireApproval ?? _foundChat?.requireApproval ?? false;

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
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Name input - only show if name not already set
          if (_needsName) ...[
            const SizedBox(height: 24),
            Text(
              l10n.enterNameToJoin,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: l10n.yourDisplayName,
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isJoining,
              onSubmitted: (_) => _joinChat(),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.nameVisibleNotice,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],

          // Approval notice
          if (requireApproval) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.requiresApprovalNotice,
                      style: TextStyle(color: Colors.orange.shade800),
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
