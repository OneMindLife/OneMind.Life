import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_log_service.dart';

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

/// Label stored alongside each token so the server can shape the FCM
/// message per platform (web gets data-only for the service worker;
/// mobile gets a `notification` block so the OS renders it natively).
String pushPlatformLabel() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return defaultTargetPlatform.name;
  }
}

class PushNotificationService {
  final SupabaseClient _client;
  bool _initialized = false;

  PushNotificationService(this._client);

  static const _vapidKey =
      'BAIuf37ss69F23wPAa7z_pXwK3ym1GWaEZes45Nj847qH2Ry-Qqk86ifmOyN9A2kSQnQAjy-Oaw-n3IS76Nz92c';

  /// Firebase init in main.dart is non-fatal by design — if it failed (or
  /// we're in a test environment without a Firebase app), push must degrade
  /// silently rather than crash the caller.
  FirebaseMessaging? get _messagingOrNull {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  /// Read the current permission status without prompting the user.
  /// Returns null when Firebase isn't available.
  Future<AuthorizationStatus?> getPermissionStatus() async {
    final messaging = _messagingOrNull;
    if (messaging == null) return null;
    final settings = await messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// True iff we should surface the "Enable notifications" opt-in UI — i.e.
  /// the user has never been asked yet. Denied/authorized users are left
  /// alone (re-prompting is a browser no-op for denied).
  Future<bool> shouldShowPermissionPrompt() async {
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
    if (_initialized) return;
    _initialized = true;

    final messaging = _messagingOrNull;
    if (messaging == null) return;

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
    await RemoteLog.log('push', 'requestAndRegister: start');

    final messaging = _messagingOrNull;
    if (messaging == null) {
      await RemoteLog.log('push', 'requestAndRegister: Firebase unavailable');
      return AuthorizationStatus.denied;
    }
    AuthorizationStatus status;
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      status = settings.authorizationStatus;
    } catch (e) {
      await RemoteLog.log('push', 'requestPermission threw', {'error': e.toString()});
      rethrow;
    }
    await RemoteLog.log('push', 'permission result', {'status': status.toString()});

    if (status == AuthorizationStatus.authorized) {
      await _registerToken();
      messaging.onTokenRefresh.listen(_saveToken);
      _initialized = true;
    } else {
      await RemoteLog.log('push', 'not authorized — skipping token register', {'status': status.toString()});
    }

    return status;
  }

  Future<void> _registerToken() async {
    try {
      await RemoteLog.log('push', 'getToken: start');
      // The VAPID key only applies to web push; mobile platforms get their
      // token from FCM/APNs directly.
      final token = await FirebaseMessaging.instance
          .getToken(vapidKey: kIsWeb ? _vapidKey : null);
      if (token == null) {
        await RemoteLog.log('push', 'getToken returned null');
        debugPrint('[Push] Failed to get FCM token');
        return;
      }
      await RemoteLog.log('push', 'getToken ok', {
        'token_preview':
            token.substring(0, token.length > 16 ? 16 : token.length),
      });
      await _saveToken(token);
    } catch (e) {
      await RemoteLog.log('push', 'getToken threw', {'error': e.toString()});
    }
  }

  Future<void> _saveToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      await RemoteLog.log('push', 'saveToken: userId null (not authenticated)');
      return;
    }

    try {
      await _client.from('fcm_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': pushPlatformLabel(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'token',
      );
      await RemoteLog.log('push', 'saveToken ok', {'user_id': userId});
    } catch (e) {
      await RemoteLog.log('push', 'saveToken upsert threw', {
        'error': e.toString(),
        'user_id': userId,
      });
    }
  }
}
