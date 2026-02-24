import 'dart:math';

/// Generates Google Docs-style random display names (adjective + animal).
/// Used to auto-assign display names to new users so they never need
/// to be prompted for a name during join/create flows.
class RandomNameGenerator {
  static const _adjectives = [
    'Happy',
    'Brave',
    'Calm',
    'Clever',
    'Kind',
    'Bold',
    'Swift',
    'Gentle',
    'Bright',
    'Wise',
    'Eager',
    'Witty',
    'Keen',
    'Noble',
    'Merry',
    'Lively',
    'Steady',
    'Warm',
    'Quick',
    'Serene',
    'Daring',
    'Loyal',
    'Nimble',
    'Proud',
    'Vivid',
    'Placid',
    'Jolly',
    'Cosmic',
    'Radiant',
    'Zesty',
  ];

  static const _animals = [
    'Dolphin',
    'Fox',
    'Owl',
    'Bear',
    'Eagle',
    'Wolf',
    'Hawk',
    'Panda',
    'Tiger',
    'Falcon',
    'Otter',
    'Lynx',
    'Raven',
    'Crane',
    'Heron',
    'Parrot',
    'Koala',
    'Jaguar',
    'Finch',
    'Bison',
    'Puma',
    'Gecko',
    'Robin',
    'Ibis',
    'Oriole',
    'Quail',
    'Wren',
    'Lark',
    'Seal',
    'Dove',
  ];

  static String generate() {
    final random = Random();
    final adj = _adjectives[random.nextInt(_adjectives.length)];
    final animal = _animals[random.nextInt(_animals.length)];
    return '$adj $animal';
  }
}
