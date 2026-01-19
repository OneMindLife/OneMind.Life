import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/invite_service.dart';
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

  // Token-based invite data
  InviteTokenResult? _inviteResult;

  // Code-based lookup data
  Chat? _foundChat;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
    _initializeInvite();
  }

  void _loadDisplayName() {
    final authService = ref.read(authServiceProvider);
    final name = authService.displayName;
    if (name != null && name.isNotEmpty) {
      _nameController.text = name;
    }
  }

  Future<void> _initializeInvite() async {
    if (widget.token != null) {
      await _validateToken();
    } else if (widget.code != null) {
      await _lookupByCode();
    } else {
      setState(() {
        _error = 'No invite token or code provided';
        _isLoading = false;
      });
    }
  }

  Future<void> _validateToken() async {
    try {
      final inviteService = ref.read(inviteServiceProvider);
      final result = await inviteService.validateInviteToken(widget.token!);

      if (result == null || !result.isValid) {
        setState(() {
          _error = 'This invite link is invalid or has expired';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _inviteResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to validate invite';
        _isLoading = false;
      });
    }
  }

  Future<void> _lookupByCode() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final chat = await chatService.getChatByCode(widget.code!);

      if (chat == null) {
        setState(() {
          _error = 'Chat not found';
          _isLoading = false;
        });
        return;
      }

      // For invite-only chats accessed via code URL, redirect to home
      // since they need to enter their email to validate access
      final inviteOnly = await inviteService.isInviteOnly(chat.id);
      if (inviteOnly) {
        setState(() {
          _error = 'This chat requires an email invite. Please use the invite link sent to your email.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _foundChat = chat;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to find chat';
        _isLoading = false;
      });
    }
  }

  Future<void> _joinChat() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name');
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
          _error = 'No chat found';
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Join request sent. Waiting for host approval.'),
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
        _error = 'Failed to join chat: $e';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Chat'),
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
              'Invalid Invite',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'This invite link is not valid.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinForm() {
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
                              "You're invited to join",
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
                                'Hosted by $hostDisplayName',
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
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Name input
          Text(
            'Enter your name to join:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Your display name',
            ),
            textCapitalization: TextCapitalization.words,
            enabled: !_isJoining,
            onSubmitted: (_) => _joinChat(),
          ),
          const SizedBox(height: 8),
          Text(
            'This name will be visible to other participants.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),

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
                      'This chat requires host approval to join.',
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
                : Text(requireApproval ? 'Request to Join' : 'Join Chat'),
          ),

          const SizedBox(height: 12),

          // Cancel button
          TextButton(
            onPressed: _isJoining ? null : () => context.go('/'),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
