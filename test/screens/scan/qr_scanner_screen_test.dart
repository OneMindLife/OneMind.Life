import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/scan/invite_code_parser.dart';

void main() {
  group('extractInviteCode', () {
    test('extracts code from full onemind.life URL', () {
      expect(extractInviteCode('https://onemind.life/join/ABC123'), 'ABC123');
    });

    test('extracts code from URL with trailing slash', () {
      expect(extractInviteCode('https://onemind.life/join/ABC123/'), 'ABC123');
    });

    test('extracts code from URL with query params', () {
      expect(extractInviteCode('https://onemind.life/join/ABC123?ref=qr'), 'ABC123');
    });

    test('extracts code from URL with hash fragment', () {
      expect(extractInviteCode('https://onemind.life/join/ABC123#section'), 'ABC123');
    });

    test('extracts code from localhost URL', () {
      expect(extractInviteCode('http://localhost:3000/join/XYZ789'), 'XYZ789');
    });

    test('extracts bare 6-char code', () {
      expect(extractInviteCode('G4N6HZ'), 'G4N6HZ');
    });

    test('uppercases bare code', () {
      expect(extractInviteCode('g4n6hz'), 'G4N6HZ');
    });

    test('uppercases URL code', () {
      expect(extractInviteCode('https://onemind.life/join/g4n6hz'), 'G4N6HZ');
    });

    test('returns null for too-short code', () {
      expect(extractInviteCode('ABC'), isNull);
    });

    test('returns null for too-long code', () {
      expect(extractInviteCode('ABCDEFG'), isNull);
    });

    test('returns null for random URL', () {
      expect(extractInviteCode('https://google.com'), isNull);
    });

    test('returns null for empty string', () {
      expect(extractInviteCode(''), isNull);
    });

    test('returns null for URL without join path', () {
      expect(extractInviteCode('https://onemind.life/about'), isNull);
    });

    test('returns null for code with special characters', () {
      expect(extractInviteCode('AB!@#D'), isNull);
    });

    test('handles whitespace around bare code', () {
      expect(extractInviteCode('  G4N6HZ  '), 'G4N6HZ');
    });
  });
}
