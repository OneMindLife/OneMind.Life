import 'package:supabase_flutter/supabase_flutter.dart';

/// Simple remote logger that writes to client_logs table.
/// Use for debugging production issues remotely.
class RemoteLog {
  static final _client = Supabase.instance.client;

  static Future<void> log(String event, String message, [Map<String, dynamic>? metadata]) async {
    try {
      await _client.from('client_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'event': event,
        'message': message,
        'metadata': metadata,
      });
    } catch (_) {
      // Silently fail — logging should never break the app
    }
  }
}
