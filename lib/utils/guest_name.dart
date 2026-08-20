import 'dart:math';

/// Random guest display name for zero-friction entry points (the official
/// GLOBAL chat auto-join). Names elsewhere are user-typed — this exists only
/// where the name gate would cost us the visitor. The user can rename
/// themselves from Home at any time.
String generateGuestName([Random? rng]) {
  final r = rng ?? Random();
  // 4 digits, never leading-zero-ambiguous: 1000–9999.
  return 'Guest ${1000 + r.nextInt(9000)}';
}
