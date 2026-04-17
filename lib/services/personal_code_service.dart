import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_exception.dart';
import '../models/personal_code.dart';

class PersonalCodeService {
  final SupabaseClient _client;

  PersonalCodeService(this._client);

  /// Generate a new personal code for a chat (host only).
  Future<PersonalCode> generateCode(int chatId) async {
    final response = await _client.rpc(
      'generate_personal_code',
      params: {'p_chat_id': chatId},
    );

    final list = response as List;
    if (list.isEmpty) {
      throw AppException.serverError(message: 'Failed to generate code');
    }
    return PersonalCode.fromJson(list.first as Map<String, dynamic>);
  }

  /// List all personal codes for a chat (host only).
  Future<List<PersonalCode>> listCodes(int chatId) async {
    final response = await _client.rpc(
      'list_personal_codes',
      params: {'p_chat_id': chatId},
    );

    return (response as List)
        .map((json) => PersonalCode.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Revoke an unused personal code (host only).
  Future<void> revokeCode(int codeId) async {
    await _client.rpc(
      'revoke_personal_code',
      params: {'p_code_id': codeId},
    );
  }

  /// Reserve a personal code for the current user.
  /// Called automatically when looking up a personal_code chat.
  /// Best-effort: failures are silently ignored.
  Future<void> reserveCode(String code) async {
    try {
      await _client.rpc(
        'reserve_personal_code',
        params: {'p_code': code.toUpperCase()},
      );
    } catch (_) {
      // Best-effort — don't block the join flow
    }
  }

  /// Release a personal code reservation.
  /// Called when the user backs out of the join dialog without joining.
  Future<void> releaseReservation(String code) async {
    try {
      await _client.rpc(
        'release_personal_code_reservation',
        params: {'p_code': code.toUpperCase()},
      );
    } catch (_) {
      // Best-effort
    }
  }

  /// Redeem a personal code to join a chat.
  /// Returns a map with participant and chat info.
  Future<Map<String, dynamic>> redeemCode({
    required String code,
    required String displayName,
  }) async {
    final response = await _client.rpc(
      'redeem_personal_code',
      params: {
        'p_code': code.toUpperCase(),
        'p_display_name': displayName,
      },
    );

    final list = response as List;
    if (list.isEmpty) {
      throw AppException.chatNotFound(inviteCode: code);
    }
    return list.first as Map<String, dynamic>;
  }
}
