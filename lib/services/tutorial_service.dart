import 'package:shared_preferences/shared_preferences.dart';

/// Service for tracking tutorial completion state
class TutorialService {
  static const String _tutorialCompletedKey = 'tutorial_completed';

  final SharedPreferences _prefs;

  TutorialService(this._prefs);

  /// Check if the user has completed the tutorial
  bool get hasCompletedTutorial {
    return _prefs.getBool(_tutorialCompletedKey) ?? false;
  }

  /// Mark the tutorial as completed
  Future<void> markTutorialComplete() async {
    await _prefs.setBool(_tutorialCompletedKey, true);
  }

  /// Reset the tutorial state (for testing or allowing replay)
  Future<void> resetTutorial() async {
    await _prefs.remove(_tutorialCompletedKey);
  }

  // =========================================================================
  // HOME TOUR
  // =========================================================================

  static const String _homeTourCompletedKey = 'home_tour_completed';

  /// Check if the user has completed the home screen tour
  bool get hasCompletedHomeTour {
    return _prefs.getBool(_homeTourCompletedKey) ?? false;
  }

  /// Mark the home screen tour as completed
  Future<void> markHomeTourComplete() async {
    await _prefs.setBool(_homeTourCompletedKey, true);
  }

  /// Reset the home tour state (for testing or allowing replay)
  Future<void> resetHomeTour() async {
    await _prefs.remove(_homeTourCompletedKey);
  }

  // =========================================================================
  // OFFICIAL-CHAT AUTO-JOIN
  // =========================================================================

  static const String _officialAutoJoinedKey = 'official_chat_auto_joined';

  /// Whether we've already attempted to auto-join the user into the
  /// official OneMind chat. Set on first visit to the home screen so we
  /// never silently re-add a user who has explicitly left.
  bool get hasAutoJoinedOfficial {
    return _prefs.getBool(_officialAutoJoinedKey) ?? false;
  }

  Future<void> markOfficialAutoJoined() async {
    await _prefs.setBool(_officialAutoJoinedKey, true);
  }

  // =========================================================================
  // PUSH NOTIFICATION PROMPT
  // =========================================================================

  static const String _pushPromptDismissedKey = 'push_prompt_dismissed';

  /// Whether the user has dismissed the "Enable notifications" banner on the
  /// home screen. Once dismissed we don't show it again.
  bool get hasDismissedPushPrompt {
    return _prefs.getBool(_pushPromptDismissedKey) ?? false;
  }

  Future<void> markPushPromptDismissed() async {
    await _prefs.setBool(_pushPromptDismissedKey, true);
  }
}
