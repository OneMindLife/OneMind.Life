import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/utils/guest_name.dart';

void main() {
  group('generateGuestName', () {
    test('matches "Guest NNNN" with a 4-digit number', () {
      for (var i = 0; i < 50; i++) {
        final name = generateGuestName();
        expect(RegExp(r'^Guest \d{4}$').hasMatch(name), isTrue,
            reason: 'got "$name"');
        final n = int.parse(name.split(' ')[1]);
        expect(n, inInclusiveRange(1000, 9999));
      }
    });

    test('is deterministic for a seeded RNG', () {
      expect(generateGuestName(Random(42)), generateGuestName(Random(42)));
    });

    test('varies across draws', () {
      final names = {for (var i = 0; i < 30; i++) generateGuestName()};
      expect(names.length, greaterThan(1));
    });
  });
}
