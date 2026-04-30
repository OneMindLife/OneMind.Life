import 'package:shared_preferences/shared_preferences.dart';

/// Throttles when the convergence-reached "Support OneMind" dialog
/// can be shown so users aren't asked on every single convergence.
class DonatePromptService {
  /// Minimum gap between two donate prompts (any source).
  static const Duration cooldown = Duration(days: 7);

  static const String _lastShownKey = 'donate_prompt_last_shown_at';
  static const String _everDonatedKey = 'donate_prompt_ever_donated';

  final SharedPreferences _prefs;

  DonatePromptService(this._prefs);

  /// Whether enough time has passed since the last prompt.
  /// Also returns false if the user has marked themselves as a donor.
  bool canShow({DateTime? now}) {
    if (_prefs.getBool(_everDonatedKey) ?? false) return false;
    final last = _prefs.getInt(_lastShownKey);
    if (last == null) return true;
    final lastShown = DateTime.fromMillisecondsSinceEpoch(last);
    return (now ?? DateTime.now()).difference(lastShown) >= cooldown;
  }

  Future<void> markShown({DateTime? now}) async {
    await _prefs.setInt(
      _lastShownKey,
      (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  /// Permanently silences the prompt — e.g. once the user has donated.
  Future<void> markEverDonated() async {
    await _prefs.setBool(_everDonatedKey, true);
  }
}
