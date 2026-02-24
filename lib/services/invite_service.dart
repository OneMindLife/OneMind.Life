import 'package:supabase_flutter/supabase_flutter.dart';

class InviteService {
  final SupabaseClient _supabase;

  InviteService(this._supabase);

  /// Create an invite for an email address and optionally send the invite email.
  ///
  /// Returns the invite token on success.
  Future<String> createInvite({
    required int chatId,
    required String email,
    required int invitedByParticipantId,
    required String chatName,
    required String inviteCode,
    String? inviterName,
    String? message,
  }) async {
    // Insert invite record
    final result = await _supabase
        .from('invites')
        .insert({
          'chat_id': chatId,
          'email': email.toLowerCase().trim(),
          'invited_by': invitedByParticipantId,
        })
        .select('invite_token')
        .single();

    final inviteToken = result['invite_token'] as String;

    // Send invite email via Edge Function
    // Use inviteToken for the email link (works for all access methods)
    try {
      await _supabase.functions.invoke('send-email', body: {
        'type': 'invite',
        'to': email.toLowerCase().trim(),
        'chatName': chatName,
        'inviteToken': inviteToken,
        'inviteCode': inviteCode.isNotEmpty ? inviteCode : null,
        'inviterName': inviterName,
        'message': message,
      });
    } catch (_) {
      // Silently fail - invite record was created
      // User can still join via the invite link
    }

    return inviteToken;
  }

  /// Send invites to multiple email addresses.
  ///
  /// Returns a map of email -> invite_token for successful invites.
  /// Emails that fail are skipped.
  Future<Map<String, String>> sendInvites({
    required int chatId,
    required List<String> emails,
    required int invitedByParticipantId,
    required String chatName,
    required String inviteCode,
    String? inviterName,
    String? message,
  }) async {
    final results = <String, String>{};

    for (final email in emails) {
      try {
        final token = await createInvite(
          chatId: chatId,
          email: email,
          invitedByParticipantId: invitedByParticipantId,
          chatName: chatName,
          inviteCode: inviteCode,
          inviterName: inviterName,
          message: message,
        );
        results[email] = token;
      } catch (e) {
        // Skip failed invites but continue with others
      }
    }

    return results;
  }

  /// Get pending invites for a chat.
  Future<List<Map<String, dynamic>>> getPendingInvites(int chatId) async {
    final result = await _supabase
        .from('invites')
        .select()
        .eq('chat_id', chatId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Resend an invite email.
  Future<void> resendInvite({
    required String inviteToken,
    required String email,
    required String chatName,
    required String inviteCode,
    String? inviterName,
    String? message,
  }) async {
    await _supabase.functions.invoke('send-email', body: {
      'type': 'invite',
      'to': email.toLowerCase().trim(),
      'chatName': chatName,
      'inviteCode': inviteCode,
      'inviterName': inviterName,
      'message': message,
    });
  }

  /// Cancel a pending invite.
  Future<void> cancelInvite(String inviteToken) async {
    await _supabase
        .from('invites')
        .update({'status': 'expired'})
        .eq('invite_token', inviteToken);
  }

  /// Validate an invite by email for a specific chat.
  ///
  /// Returns the invite token if valid, null otherwise.
  Future<String?> validateInviteByEmail({
    required int chatId,
    required String email,
  }) async {
    final result = await _supabase
        .rpc('validate_invite_email', params: {
          'p_chat_id': chatId,
          'p_email': email.toLowerCase().trim(),
        });

    if (result != null && result is List && result.isNotEmpty) {
      return result[0]['invite_token'] as String?;
    }
    return null;
  }

  /// Accept an invite after successful join.
  ///
  /// Returns true if the invite was successfully accepted.
  Future<bool> acceptInvite({
    required String inviteToken,
    required int participantId,
  }) async {
    final result = await _supabase
        .rpc('accept_invite', params: {
          'p_invite_token': inviteToken,
          'p_participant_id': participantId,
        });

    return result == true;
  }

  /// Check if a chat requires invite validation.
  ///
  /// Returns true if the chat uses invite-only access method.
  Future<bool> isInviteOnly(int chatId) async {
    final result = await _supabase
        .from('chats')
        .select('access_method')
        .eq('id', chatId)
        .single();

    return result['access_method'] == 'invite_only';
  }

  /// Validate an invite by token (from direct link).
  ///
  /// Returns invite details including chat info, or null if invalid/expired.
  Future<InviteTokenResult?> validateInviteToken(String token) async {
    try {
      final result = await _supabase.rpc('validate_invite_token', params: {
        'p_invite_token': token,
      });

      if (result != null && result is List && result.isNotEmpty) {
        final data = result[0] as Map<String, dynamic>;
        return InviteTokenResult(
          isValid: data['is_valid'] as bool? ?? false,
          chatId: data['chat_id'] as int,
          chatName: data['chat_name'] as String,
          chatInitialMessage: data['chat_initial_message'] as String,
          accessMethod: data['access_method'] as String,
          requireApproval: data['require_approval'] as bool? ?? false,
          email: data['email'] as String,
          translationLanguages:
              (data['translation_languages'] as List<dynamic>?)
                      ?.map((e) => e as String)
                      .toList() ??
                  const ['en'],
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

/// Result from validating an invite token
class InviteTokenResult {
  final bool isValid;
  final int chatId;
  final String chatName;
  final String chatInitialMessage;
  final String accessMethod;
  final bool requireApproval;
  final String email;
  final List<String> translationLanguages;

  InviteTokenResult({
    required this.isValid,
    required this.chatId,
    required this.chatName,
    required this.chatInitialMessage,
    required this.accessMethod,
    required this.requireApproval,
    required this.email,
    this.translationLanguages = const ['en'],
  });
}
