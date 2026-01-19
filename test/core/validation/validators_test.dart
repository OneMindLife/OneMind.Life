import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/core/validation/validators.dart';

void main() {
  group('ValidationResult', () {
    test('valid result has isValid true', () {
      const result = ValidationResult.valid();
      expect(result.isValid, true);
      expect(result.errorMessage, null);
    });

    test('invalid result has isValid false', () {
      const result = ValidationResult.invalid('Error message', field: 'test');
      expect(result.isValid, false);
      expect(result.errorMessage, 'Error message');
      expect(result.field, 'test');
    });

    test('toException returns null for valid result', () {
      const result = ValidationResult.valid();
      expect(result.toException(), null);
    });

    test('toException returns AppException for invalid result', () {
      const result = ValidationResult.invalid('Error', field: 'test');
      final exception = result.toException();
      expect(exception, isNotNull);
      expect(exception!.message, 'Error');
    });
  });

  group('TextValidators', () {
    group('required()', () {
      test('returns valid for non-empty string', () {
        final result = TextValidators.required('hello');
        expect(result.isValid, true);
      });

      test('returns invalid for null', () {
        final result = TextValidators.required(null, fieldName: 'Name');
        expect(result.isValid, false);
        expect(result.errorMessage, 'Name is required');
      });

      test('returns invalid for empty string', () {
        final result = TextValidators.required('');
        expect(result.isValid, false);
      });

      test('returns invalid for whitespace only', () {
        final result = TextValidators.required('   ');
        expect(result.isValid, false);
      });
    });

    group('minLength()', () {
      test('returns valid when length meets minimum', () {
        final result = TextValidators.minLength('hello', 5);
        expect(result.isValid, true);
      });

      test('returns valid when length exceeds minimum', () {
        final result = TextValidators.minLength('hello world', 5);
        expect(result.isValid, true);
      });

      test('returns invalid when length below minimum', () {
        final result = TextValidators.minLength('hi', 5, fieldName: 'Name');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('at least 5 characters'));
      });

      test('returns invalid for null', () {
        final result = TextValidators.minLength(null, 1);
        expect(result.isValid, false);
      });
    });

    group('maxLength()', () {
      test('returns valid when length below maximum', () {
        final result = TextValidators.maxLength('hello', 10);
        expect(result.isValid, true);
      });

      test('returns valid when length equals maximum', () {
        final result = TextValidators.maxLength('hello', 5);
        expect(result.isValid, true);
      });

      test('returns invalid when length exceeds maximum', () {
        final result = TextValidators.maxLength('hello world', 5, fieldName: 'Name');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('at most 5 characters'));
      });

      test('returns valid for null', () {
        final result = TextValidators.maxLength(null, 10);
        expect(result.isValid, true);
      });
    });

    group('lengthRange()', () {
      test('returns valid when length in range', () {
        final result = TextValidators.lengthRange('hello', min: 3, max: 10);
        expect(result.isValid, true);
      });

      test('returns invalid when length below range', () {
        final result = TextValidators.lengthRange('hi', min: 3, max: 10);
        expect(result.isValid, false);
      });

      test('returns invalid when length above range', () {
        final result =
            TextValidators.lengthRange('hello world test', min: 3, max: 10);
        expect(result.isValid, false);
      });
    });

    group('email()', () {
      test('returns valid for correct email', () {
        final result = TextValidators.email('test@example.com');
        expect(result.isValid, true);
      });

      test('returns valid for email with subdomain', () {
        final result = TextValidators.email('user@mail.example.com');
        expect(result.isValid, true);
      });

      test('returns invalid for missing @', () {
        final result = TextValidators.email('testexample.com');
        expect(result.isValid, false);
      });

      test('returns invalid for missing domain', () {
        final result = TextValidators.email('test@');
        expect(result.isValid, false);
      });

      test('returns invalid for empty', () {
        final result = TextValidators.email('');
        expect(result.isValid, false);
      });
    });

    group('inviteCode()', () {
      test('returns valid for uppercase alphanumeric', () {
        final result = TextValidators.inviteCode('ABC123');
        expect(result.isValid, true);
      });

      test('converts to uppercase and validates', () {
        final result = TextValidators.inviteCode('abc123');
        expect(result.isValid, true);
      });

      test('returns invalid for too short', () {
        final result = TextValidators.inviteCode('AB');
        expect(result.isValid, false);
      });

      test('returns invalid for special characters', () {
        final result = TextValidators.inviteCode('ABC-123');
        expect(result.isValid, false);
      });

      test('returns invalid for empty', () {
        final result = TextValidators.inviteCode('');
        expect(result.isValid, false);
      });
    });

    group('sanitize()', () {
      test('removes control characters', () {
        expect(TextValidators.sanitize('hello\x00world'), 'helloworld');
      });

      test('trims whitespace', () {
        expect(TextValidators.sanitize('  hello  world  '), 'hello world');
      });

      test('collapses multiple spaces', () {
        expect(TextValidators.sanitize('hello    world'), 'hello world');
      });

      test('limits length to 10000 characters', () {
        final longString = 'a' * 20000;
        final result = TextValidators.sanitize(longString);
        expect(result.length, 10000);
      });
    });

    group('noMaliciousContent()', () {
      test('returns valid for normal text', () {
        final result = TextValidators.noMaliciousContent('Hello world');
        expect(result.isValid, true);
      });

      test('returns invalid for script tags', () {
        final result = TextValidators.noMaliciousContent('<script>alert(1)</script>');
        expect(result.isValid, false);
      });

      test('returns invalid for SQL injection patterns', () {
        final result = TextValidators.noMaliciousContent("'; DROP TABLE users;--");
        expect(result.isValid, false);
      });

      test('returns valid for null', () {
        final result = TextValidators.noMaliciousContent(null);
        expect(result.isValid, true);
      });
    });
  });

  group('NumberValidators', () {
    group('range()', () {
      test('returns valid when in range', () {
        final result = NumberValidators.range(50, min: 1, max: 100);
        expect(result.isValid, true);
      });

      test('returns valid at minimum', () {
        final result = NumberValidators.range(1, min: 1, max: 100);
        expect(result.isValid, true);
      });

      test('returns valid at maximum', () {
        final result = NumberValidators.range(100, min: 1, max: 100);
        expect(result.isValid, true);
      });

      test('returns invalid below range', () {
        final result = NumberValidators.range(0, min: 1, max: 100);
        expect(result.isValid, false);
      });

      test('returns invalid above range', () {
        final result = NumberValidators.range(101, min: 1, max: 100);
        expect(result.isValid, false);
      });

      test('returns invalid for null', () {
        final result = NumberValidators.range(null, min: 1, max: 100);
        expect(result.isValid, false);
      });
    });

    group('positive()', () {
      test('returns valid for positive number', () {
        final result = NumberValidators.positive(1);
        expect(result.isValid, true);
      });

      test('returns invalid for zero', () {
        final result = NumberValidators.positive(0);
        expect(result.isValid, false);
      });

      test('returns invalid for negative', () {
        final result = NumberValidators.positive(-1);
        expect(result.isValid, false);
      });
    });

    group('nonNegative()', () {
      test('returns valid for positive number', () {
        final result = NumberValidators.nonNegative(1);
        expect(result.isValid, true);
      });

      test('returns valid for zero', () {
        final result = NumberValidators.nonNegative(0);
        expect(result.isValid, true);
      });

      test('returns invalid for negative', () {
        final result = NumberValidators.nonNegative(-1);
        expect(result.isValid, false);
      });
    });

    group('integer()', () {
      test('returns valid for integer', () {
        final result = NumberValidators.integer(5);
        expect(result.isValid, true);
      });

      test('returns invalid for decimal', () {
        final result = NumberValidators.integer(5.5);
        expect(result.isValid, false);
      });

      test('returns invalid for null', () {
        final result = NumberValidators.integer(null);
        expect(result.isValid, false);
      });
    });

    group('credits()', () {
      test('returns valid for minimum credits', () {
        final result = NumberValidators.credits(1);
        expect(result.isValid, true);
      });

      test('returns valid for maximum credits', () {
        final result = NumberValidators.credits(100000);
        expect(result.isValid, true);
      });

      test('returns invalid for zero', () {
        final result = NumberValidators.credits(0);
        expect(result.isValid, false);
      });

      test('returns invalid for over maximum', () {
        final result = NumberValidators.credits(100001);
        expect(result.isValid, false);
      });

      test('returns invalid for null', () {
        final result = NumberValidators.credits(null);
        expect(result.isValid, false);
      });
    });
  });

  group('ChatValidators', () {
    group('chatName()', () {
      test('returns valid for proper name', () {
        final result = ChatValidators.chatName('My Chat');
        expect(result.isValid, true);
      });

      test('returns invalid for too short', () {
        final result = ChatValidators.chatName('AB');
        expect(result.isValid, false);
      });

      test('returns invalid for empty', () {
        final result = ChatValidators.chatName('');
        expect(result.isValid, false);
      });

      test('returns invalid for too long', () {
        final result = ChatValidators.chatName('a' * 101);
        expect(result.isValid, false);
      });

      test('returns invalid for malicious content', () {
        final result = ChatValidators.chatName('<script>alert(1)</script>');
        expect(result.isValid, false);
      });
    });

    group('propositionContent()', () {
      test('returns valid for normal content', () {
        final result = ChatValidators.propositionContent('This is my proposal');
        expect(result.isValid, true);
      });

      test('returns invalid for empty', () {
        final result = ChatValidators.propositionContent('');
        expect(result.isValid, false);
      });

      test('returns invalid for too long', () {
        final result = ChatValidators.propositionContent('a' * 501);
        expect(result.isValid, false);
      });
    });

    group('timerDuration()', () {
      test('returns valid for 1 minute', () {
        final result = ChatValidators.timerDuration(60);
        expect(result.isValid, true);
      });

      test('returns invalid for less than 30 seconds', () {
        final result = ChatValidators.timerDuration(15);
        expect(result.isValid, false);
      });

      test('returns invalid for over 24 hours', () {
        final result = ChatValidators.timerDuration(86401);
        expect(result.isValid, false);
      });
    });

    group('confirmationRounds()', () {
      test('returns valid for 2 rounds', () {
        final result = ChatValidators.confirmationRounds(2);
        expect(result.isValid, true);
      });

      test('returns invalid for 0', () {
        final result = ChatValidators.confirmationRounds(0);
        expect(result.isValid, false);
      });

      test('returns invalid for over 10', () {
        final result = ChatValidators.confirmationRounds(11);
        expect(result.isValid, false);
      });
    });
  });

  group('ValidationChain', () {
    test('returns valid when all validations pass', () {
      final chain = ValidationChain()
          .add(TextValidators.required('hello'))
          .add(TextValidators.minLength('hello', 3))
          .add(TextValidators.maxLength('hello', 10));

      expect(chain.isValid, true);
      expect(chain.result.isValid, true);
    });

    test('returns first error when validation fails', () {
      final chain = ValidationChain()
          .add(TextValidators.required(''))
          .add(TextValidators.minLength('', 3));

      expect(chain.isValid, false);
      expect(chain.result.errorMessage, contains('required'));
    });

    test('collects all errors', () {
      final chain = ValidationChain()
          .add(TextValidators.required(''))
          .add(const ValidationResult.invalid('Second error'));

      expect(chain.errors.length, 2);
    });

    test('addIf only adds validation when condition is true', () {
      final chain = ValidationChain()
          .addIf(true, () => TextValidators.required(''))
          .addIf(false, () => const ValidationResult.invalid('Should not add'));

      expect(chain.errors.length, 1);
    });
  });
}
