import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  final SupabaseClient _client;
  bool _initialized = false;

  PushNotificationService(this._client);

  /// Request notification permission and save the FCM token.
  /// Call once after the user is signed in.
  Future<void> initialize() async {
    if (_initialized || !kIsWeb) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('[Push] Permission denied');
      return;
    }

    final token = await messaging.getToken(
      vapidKey:
          'BAIuf37ss69F23wPAa7z_pXwK3ym1GWaEZes45Nj847qH2Ry-Qqk86ifmOyN9A2kSQnQAjy-Oaw-n3IS76Nz92c',
    );

    if (token == null) {
      debugPrint('[Push] Failed to get FCM token');
      return;
    }

    await _saveToken(token);
    messaging.onTokenRefresh.listen(_saveToken);
  }

  Future<void> _saveToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('fcm_tokens').upsert(
      {
        'user_id': userId,
        'token': token,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'token',
    );
  }
}
