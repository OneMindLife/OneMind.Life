import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/push_notification_service.dart';

/// Pure-function tests for the FCM data-payload parsing used by the
/// notification-tap handlers. The handlers themselves wrap
/// FirebaseMessaging APIs that are platform-channel bound and not worth
/// mocking; the surface that's worth pinning is "given some FCM data
/// blob, what chat_id do we navigate to?"
void main() {
  group('chatIdFromNotificationData', () {
    test('returns parsed int for a numeric string', () {
      expect(chatIdFromNotificationData({'chat_id': '246'}), 246);
    });

    test('returns null when chat_id is missing', () {
      expect(chatIdFromNotificationData(const {}), isNull);
      expect(chatIdFromNotificationData({'other': 'x'}), isNull);
    });

    test('returns null for a non-numeric value', () {
      expect(chatIdFromNotificationData({'chat_id': 'not-a-number'}), isNull);
    });

    test('handles a numeric (non-string) value via toString', () {
      // FCM data values are always strings on the wire, but the Dart map
      // could carry an int if synthesized in tests / future code paths.
      expect(chatIdFromNotificationData({'chat_id': 42}), 42);
    });

    test('returns null when chat_id is explicitly null', () {
      expect(chatIdFromNotificationData({'chat_id': null}), isNull);
    });
  });
}
