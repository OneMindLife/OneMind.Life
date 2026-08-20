import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/invite_service.dart';
import '../../utils/guest_name.dart';
import '../../utils/language_utils.dart';
import '../../widgets/error_view.dart';
import '../../widgets/name_section.dart';

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

  /// Name gate: joining requires a display name (names are never
  /// auto-generated). Owned here so the Join button can gate on it.
  final _nameController = TextEditingController();

  // Token-based invite data
  InviteTokenResult? _inviteResult;

  // Code-based lookup data
  Chat? _foundChat;

  // Personal code flag — when true, join via redeem_personal_code
  bool _isPersonalCode = false;

  /// Official-chat zero-friction path: post-join navigation carries
  /// ?instant=1 so Home stays veiled behind a spinner until the chat pushes
  /// — the visitor goes URL → chat with nothing in between.
  bool _instantEntry = false;

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
        // Already a participant → REOPEN the chat (D37 re-entry fix). Was
        // `go('/')` which dumped a returning member on the marketing landing
        // instead of their chat — so re-clicking an invite link to come back
        // didn't work (verified real case: an organic invitee to chat 470 could
        // only return via browser history of the redirected URL). Must be
        // /home?chat_id — '/' is the marketing LandingScreen and ignores it.
        if (mounted) {
          context.go('/home?chat_id=${result.chatId}');
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
        // Already a participant → REOPEN the chat (D37 re-entry fix; see the
        // _lookupByInvite branch above). Must be /home?chat_id, not '/'.
        // Official chats re-enter seamlessly (?instant=1 veils Home).
        if (mounted) {
          context.go(chat.isOfficial
              ? '/home?chat_id=${chat.id}&instant=1'
              : '/home?chat_id=${chat.id}');
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
      // since they need to enter their email to validate access. Read
      // accessMethod from the chat returned by getChatByCode (which goes
      // through a SECURITY DEFINER RPC) — a direct SELECT here is blocked
      // by RLS for non-participants and surfaces as PGRST116 / 406.
      if (chat.accessMethod == AccessMethod.inviteOnly) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _error = l10n.inviteOnlyError;
            _isLoading = false;
          });
        }
        return;
      }

      // OFFICIAL chat (the GLOBAL front door): zero-friction entry. Arriving
      // via the URL IS the intent to join — no confirmation screen and NO
      // name gate. First-timers get a random guest name (editable later from
      // Home); requiring a typed name here was costing us cold arrivals.
      // Keep _isLoading true so the spinner shows until _joinChat navigates.
      if (chat.isOfficial && !chat.requireApproval) {
        final authService = ref.read(authServiceProvider);
        await authService.ensureSignedIn();
        if (!authService.hasDisplayName) {
          await authService.setDisplayName(generateGuestName());
          ref.invalidate(authDisplayNameProvider);
        }
        setState(() {
          _foundChat = chat;
          _instantEntry = true;
        });
        await _joinChat();
        return;
      }

      // Quick chats (single-cycle, host-controlled) are a frictionless sealed
      // loop — arriving via the share link IS the intent to join, so skip the
      // confirmation screen and auto-join straight into the chat. Keep _isLoading
      // true so the spinner shows (not a flash of the preview) until _joinChat
      // navigates. Approval-required chats can't auto-join (host must approve)
      // and fall through to the manual screen.
      //
      // The participant row is still created here (the host needs an accurate
      // presence count), but get_matches_rating_progress counts only people who
      // actually voted — so a peeker who opens the link and never votes does not
      // pollute the host's "who's done" count or re-trigger the end-early prompt.
      //
      // Users who haven't named themselves yet fall through to the manual
      // screen instead — its name field is the only thing between the link
      // and the chat (same gate the wedge's game mode uses).
      if (chat.maxCycles == 1 &&
          !chat.requireApproval &&
          ref.read(authServiceProvider).hasDisplayName) {
        setState(() {
          _foundChat = chat;
        });
        await _joinChat();
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
      // A fresh visitor who lands straight on /join/CODE (e.g. an incognito
      // tab following a share link) may not have an anonymous session yet —
      // guarantee one before joining.
      await authService.ensureSignedIn();
      // Name gate: use the stored display name, or save the one typed in the
      // join form. Never auto-generated — a name is required to join.
      final name = await commitNameSection(ref, _nameController);
      if (name == null) {
        setState(() {
          _error = l10n.pleaseEnterName;
          _isJoining = false;
          _isLoading = false;
        });
        return;
      }

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
          // Must be /home — the '/' route is the marketing LandingScreen and
          // ignores chat_id, so '/?chat_id=' dumped joiners on the hero page.
          context.go('/home?chat_id=$joinedChatId');
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
          // Must be /home — '/' is the marketing LandingScreen (ignores
          // chat_id), which is why joiners were landing on the hero page.
          // instant=1 (official auto-join) veils Home until the chat pushes.
          context.go(_instantEntry
              ? '/home?chat_id=$chatId&instant=1'
              : '/home?chat_id=$chatId');
        }
      }
    } catch (e) {
      setState(() {
        _error = l10n.failedToJoinChat(e.toString());
        _isJoining = false;
        // If we reached here via the quick-chat auto-join path, _isLoading is
        // still true — drop it so the error + manual Join button surface.
        _isLoading = false;
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
    // While resolving (and during auto-join) show ONLY a spinner — no
    // "Join Chat" chrome. Zero-friction paths never render anything else.
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.joinScreenTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: _error != null && _inviteResult == null && _foundChat == null
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

          // Who you'll join as: inline name field for first-timers, or a
          // "Joining as X" line with an edit pencil for named users.
          NameSection(
            controller: _nameController,
            asLabel: l10n.joiningAs,
          ),
          const SizedBox(height: 16),

          // Join button — disabled until a name exists (typed or stored).
          ListenableBuilder(
            listenable: _nameController,
            builder: (context, _) {
              final hasName = ref.read(authServiceProvider).hasDisplayName ||
                  _nameController.text.trim().isNotEmpty;
              return FilledButton(
                onPressed: _isJoining || !hasName ? null : _joinChat,
                child: _isJoining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(requireApproval
                        ? l10n.requestToJoinButton
                        : l10n.joinChatButton),
              );
            },
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
