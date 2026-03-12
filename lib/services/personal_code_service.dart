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
