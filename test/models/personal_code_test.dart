import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/personal_code.dart';

void main() {
  group('PersonalCode', () {
    group('fromJson', () {
      test('parses all fields', () {
        final json = {
          'id': 42,
          'code': 'ABC123',
          'label': 'For Alice',
          'used_by': 'user-uuid-123',
          'used_at': '2024-06-15T12:00:00Z',
          'revoked_at': '2024-06-16T08:00:00Z',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final code = PersonalCode.fromJson(json);

        expect(code.id, 42);
        expect(code.code, 'ABC123');
        expect(code.label, 'For Alice');
        expect(code.usedBy, 'user-uuid-123');
        expect(code.usedAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
        expect(code.revokedAt, DateTime.utc(2024, 6, 16, 8, 0, 0));
        expect(code.createdAt, DateTime.utc(2024, 1, 1));
      });

      test('handles null optional fields', () {
        final json = {
          'id': 1,
          'code': 'XYZ789',
          'label': null,
          'used_by': null,
          'used_at': null,
          'revoked_at': null,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final code = PersonalCode.fromJson(json);

        expect(code.id, 1);
        expect(code.code, 'XYZ789');
        expect(code.label, isNull);
        expect(code.usedBy, isNull);
        expect(code.usedAt, isNull);
        expect(code.revokedAt, isNull);
      });

      test('trims CHAR(6) trailing spaces', () {
        final json = {
          'id': 1,
          'code': 'AB    ', // CHAR(6) pads with spaces
          'created_at': '2024-01-01T00:00:00Z',
        };

        final code = PersonalCode.fromJson(json);

        expect(code.code, 'AB');
      });
    });

    group('status', () {
      test('returns active when no usedAt or revokedAt', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(code.status, PersonalCodeStatus.active);
      });

      test('returns used when usedAt is set', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          usedBy: 'user-uuid',
          usedAt: DateTime.utc(2024, 6, 15),
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(code.status, PersonalCodeStatus.used);
      });

      test('returns revoked when revokedAt is set', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          revokedAt: DateTime.utc(2024, 6, 16),
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(code.status, PersonalCodeStatus.revoked);
      });

      test('returns revoked when both usedAt and revokedAt are set', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          usedBy: 'user-uuid',
          usedAt: DateTime.utc(2024, 6, 15),
          revokedAt: DateTime.utc(2024, 6, 16),
          createdAt: DateTime.utc(2024, 1, 1),
        );

        // revokedAt takes precedence over usedAt
        expect(code.status, PersonalCodeStatus.revoked);
      });
    });

    group('isActive', () {
      test('returns true for active code', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(code.isActive, true);
      });

      test('returns false for used code', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          usedBy: 'user-uuid',
          usedAt: DateTime.utc(2024, 6, 15),
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(code.isActive, false);
      });

      test('returns false for revoked code', () {
        final code = PersonalCode(
          id: 1,
          code: 'ABC123',
          revokedAt: DateTime.utc(2024, 6, 16),
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(code.isActive, false);
      });
    });

    group('equality', () {
      test('two PersonalCodes with same fields are equal', () {
        final createdAt = DateTime.utc(2024, 1, 1);

        final code1 = PersonalCode(
          id: 1,
          code: 'ABC123',
          label: 'Test',
          createdAt: createdAt,
        );

        final code2 = PersonalCode(
          id: 1,
          code: 'ABC123',
          label: 'Test',
          createdAt: createdAt,
        );

        expect(code1, equals(code2));
      });

      test('two PersonalCodes with different fields are not equal', () {
        final createdAt = DateTime.utc(2024, 1, 1);

        final code1 = PersonalCode(
          id: 1,
          code: 'ABC123',
          createdAt: createdAt,
        );

        final code2 = PersonalCode(
          id: 2,
          code: 'XYZ789',
          createdAt: createdAt,
        );

        expect(code1, isNot(equals(code2)));
      });
    });
  });
}
