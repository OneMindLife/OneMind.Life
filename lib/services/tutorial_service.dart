import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for tracking tutorial completion state
class TutorialService {
  static const String _tutorialCompletedKey = 'tutorial_completed';

  final SharedPreferences _prefs;

  TutorialService(this._prefs);

  /// Check if the user has completed the tutorial
  bool get hasCompletedTutorial {
    final completed = _prefs.getBool(_tutorialCompletedKey) ?? false;
    if (kDebugMode) {
      debugPrint('[TutorialService] hasCompletedTutorial: $completed');
    }
    return completed;
  }

  /// Mark the tutorial as completed
  Future<void> markTutorialComplete() async {
    if (kDebugMode) {
      debugPrint('[TutorialService] Marking tutorial as complete');
    }
    await _prefs.setBool(_tutorialCompletedKey, true);
  }

  /// Reset the tutorial state (for testing or allowing replay)
  Future<void> resetTutorial() async {
    if (kDebugMode) {
      debugPrint('[TutorialService] Resetting tutorial state');
    }
    await _prefs.remove(_tutorialCompletedKey);
  }
}
