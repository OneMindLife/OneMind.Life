import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/utils/random_name_generator.dart';

void main() {
  group('RandomNameGenerator', () {
    test('generate returns "Adjective Animal" format', () {
      final name = RandomNameGenerator.generate();
      final parts = name.split(' ');
      expect(parts.length, 2, reason: 'Name should be two words');
      expect(parts[0][0], parts[0][0].toUpperCase(),
          reason: 'Adjective should be capitalized');
      expect(parts[1][0], parts[1][0].toUpperCase(),
          reason: 'Animal should be capitalized');
    });

    test('generate returns non-empty string', () {
      final name = RandomNameGenerator.generate();
      expect(name.isNotEmpty, isTrue);
      expect(name.trim(), name, reason: 'No leading/trailing whitespace');
    });

    test('generate produces different names across many calls', () {
      // With 30x30=900 combinations, 50 calls should have at least 2 unique
      final names = List.generate(50, (_) => RandomNameGenerator.generate());
      final unique = names.toSet();
      expect(unique.length, greaterThan(1),
          reason: 'Should produce varied names');
    });

    test('adjectives list has 30 entries', () {
      // Verify by generating many names and collecting adjectives
      final adjectives = <String>{};
      for (int i = 0; i < 5000; i++) {
        final name = RandomNameGenerator.generate();
        adjectives.add(name.split(' ').first);
      }
      expect(adjectives.length, 30);
    });

    test('animals list has 30 entries', () {
      // Verify by generating many names and collecting animals
      final animals = <String>{};
      for (int i = 0; i < 5000; i++) {
        final name = RandomNameGenerator.generate();
        animals.add(name.split(' ').last);
      }
      expect(animals.length, 30);
    });

    test('all generated adjectives are single capitalized words', () {
      for (int i = 0; i < 100; i++) {
        final adj = RandomNameGenerator.generate().split(' ').first;
        expect(adj, matches(RegExp(r'^[A-Z][a-z]+$')),
            reason: '"$adj" should be a single capitalized word');
      }
    });

    test('all generated animals are single capitalized words', () {
      for (int i = 0; i < 100; i++) {
        final animal = RandomNameGenerator.generate().split(' ').last;
        expect(animal, matches(RegExp(r'^[A-Z][a-z]+$')),
            reason: '"$animal" should be a single capitalized word');
      }
    });
  });
}
