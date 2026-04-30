import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parses the `chat_id` value out of an FCM notification's data payload.
/// Returns null when the field is missing or not a valid integer.
///
/// Exposed at top level so it can be unit-tested without instantiating the
/// service or its FirebaseMessaging dependency.
int? chatIdFromNotificationData(Map<String, dynamic> data) {
  final raw = data['chat_id'];
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}

class PushNotificationService {
  final SupabaseClient _client;
  bool _initialized = false;

  PushNotificationService(this._client);

  static const _vapidKey =
      'BAIuf37ss69F23wPAa7z_pXwK3ym1GWaEZes45Nj847qH2Ry-Qqk86ifmOyN9A2kSQnQAjy-Oaw-n3IS76Nz92c';

  /// Read the current permission status without prompting the user.
  /// Returns `null` on non-web platforms (we only wire web push for now).
  Future<AuthorizationStatus?> getPermissionStatus() async {
    if (!kIsWeb) return null;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// True iff we should surface the "Enable notifications" opt-in UI — i.e.
  /// we're on web and the user has never been asked yet. Denied/authorized
  /// users are left alone (re-prompting is a browser no-op for denied).
  Future<bool> shouldShowPermissionPrompt() async {
    if (!kIsWeb) return false;
    final status = await getPermissionStatus();
    return status == AuthorizationStatus.notDetermined;
  }

  /// If the user already granted notification permission, register their FCM
  /// token silently (no prompt). Safe to call on every home mount.
  ///
  /// [onTapChatId] fires when the user taps a push notification that
  /// carries a `chat_id` in its data payload — both warm-start
  /// (app already running) and cold-start (tap from closed app).
  Future<void> initialize({void Function(int chatId)? onTapChatId}) async {
    if (_initialized || !kIsWeb) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    // Wire notification-tap handlers BEFORE the permission gate so
    // cold-start taps still route even if the user granted permission
    // on an earlier session. `getInitialMessage` returns the message
    // the app was opened from; `onMessageOpenedApp` fires while the app
    // is backgrounded.
    if (onTapChatId != null) {
      _wireTapHandlers(messaging, onTapChatId);
    }

    final settings = await messaging.getNotificationSettings();

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      // Haven't been granted — wait for the user to opt in via the banner.
      return;
    }

    await _registerToken();
    messaging.onTokenRefresh.listen(_saveToken);
  }

  Future<void> _wireTapHandlers(
    FirebaseMessaging messaging,
    void Function(int chatId) onTapChatId,
  ) async {
    // Cold start — app opened from a notification tap.
    final initial = await messaging.getInitialMessage();
    final initialChatId = _chatIdFromMessage(initial);
    if (initialChatId != null) onTapChatId(initialChatId);

    // Warm start — app already running in background, user tapped a
    // notification to bring it to the foreground.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final chatId = _chatIdFromMessage(message);
      if (chatId != null) onTapChatId(chatId);
    });
  }

  int? _chatIdFromMessage(RemoteMessage? message) {
    if (message == null) return null;
    return chatIdFromNotificationData(message.data);
  }

  /// Explicitly prompt the user for notification permission and register the
  /// FCM token if they accept. Call this in response to a user gesture
  /// (e.g. tapping an "Enable notifications" button).
  Future<AuthorizationStatus> requestAndRegister() async {
    if (!kIsWeb) return AuthorizationStatus.denied;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await _registerToken();
      messaging.onTokenRefresh.listen(_saveToken);
      _initialized = true;
    }

    return settings.authorizationStatus;
  }

  Future<void> _registerToken() async {
    final token =
        await FirebaseMessaging.instance.getToken(vapidKey: _vapidKey);
    if (token == null) {
      debugPrint('[Push] Failed to get FCM token');
      return;
    }
    await _saveToken(token);
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
