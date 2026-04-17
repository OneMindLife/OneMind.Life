import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Landing page A/B test variants.
enum LandingVariant {
  /// "Decision Making" angle — teams make better decisions together.
  decisions,

  /// "Consensus Building" angle — align without endless meetings.
  consensus,
}

/// Assigns and persists A/B test variants for the landing page.
///
/// Variant is randomly assigned on first visit and persisted in
/// SharedPreferences so the user always sees the same variant.
class AbTestService {
  static const _variantKey = 'ab_landing_variant';
  final SharedPreferences _prefs;

  AbTestService(this._prefs);

  /// Returns the assigned variant, creating one if needed.
  LandingVariant getVariant() {
    final stored = _prefs.getString(_variantKey);
    if (stored != null) {
      for (final v in LandingVariant.values) {
        if (v.name == stored) return v;
      }
    }
    return _assignVariant();
  }

  LandingVariant _assignVariant() {
    final variant = LandingVariant
        .values[Random().nextInt(LandingVariant.values.length)];
    _prefs.setString(_variantKey, variant.name);
    return variant;
  }
}
