import 'dart:async';

/// Single-active-audio arbiter shared between narration (TtsButton) and
/// video-card audio (ConvergenceVideoCard). Only one **foreground** source
/// is "active" at a time; claiming playback asks the previous source to
/// stop/mute.
///
/// A separate **background** layer (e.g. chat ambience in
/// [BackgroundAudioService]) can register a pause/resume pair via
/// [registerBackground]. It is automatically paused while any foreground
/// source is active and resumed when the foreground slot goes empty.
typedef StopCallback = FutureOr<void> Function();

/// Handle returned when registering a background source. Keep the reference
/// so you can pass it back to [ActiveAudio.unregisterBackground] on dispose.
class BackgroundAudioHandle {
  final FutureOr<void> Function() pause;
  final FutureOr<void> Function() resume;

  BackgroundAudioHandle({required this.pause, required this.resume});
}

class ActiveAudio {
  static StopCallback? _currentStop;
  static BackgroundAudioHandle? _bg;

  /// True iff a foreground source is currently active.
  static bool get isForegroundActive => _currentStop != null;

  /// Register a background source. It will be asked to pause whenever a
  /// foreground source becomes active, and resume when the foreground slot
  /// goes empty again.
  ///
  /// If a foreground source is already active at registration time, the
  /// background will NOT be auto-paused (it hasn't started yet); callers
  /// should gate their own first `play()` on [isForegroundActive].
  static void registerBackground(BackgroundAudioHandle handle) {
    _bg = handle;
  }

  /// Clear the background source if it is this one. No-op otherwise.
  /// [BackgroundAudioHandle] is a plain object (not a Function tear-off), so
  /// [identical] is the right comparator here.
  static void unregisterBackground(BackgroundAudioHandle handle) {
    if (identical(_bg, handle)) _bg = null;
  }

  /// Register this source as the active audio and ask the previous one to stop.
  /// Pass the same [stop] callback that will be given to [release] when this
  /// source finishes on its own.
  static Future<void> claim(StopCallback stop) async {
    final wasEmpty = _currentStop == null;
    final prev = _currentStop;
    _currentStop = stop;
    // Use `==` (not `identical`) because method tear-offs produce new
    // Function objects on each access but compare equal by (receiver, method).
    if (prev != null && prev != stop) {
      try {
        await prev();
      } catch (_) {
        // Ignore stop failures — best-effort.
      }
    }
    // Only pause the background on the 0→1 transition. Subsequent claim
    // baton-passes don't need to touch it (it's already paused).
    if (wasEmpty && _bg != null) {
      try {
        await _bg!.pause();
      } catch (_) {}
    }
  }

  /// Fire the currently-active stop callback (if any) and clear the slot.
  /// Used when a host screen tears down and wants an immediate hard-stop
  /// of any narration/video audio, rather than waiting for child-widget
  /// dispose to cascade. Does NOT trigger the background resume callback,
  /// because callers are typically leaving the audio-enabled scope.
  static Future<void> stopForeground() async {
    final stop = _currentStop;
    _currentStop = null;
    if (stop != null) {
      try {
        await stop();
      } catch (_) {}
    }
  }

  /// Clear the active source if it is this one. No-op otherwise. When the
  /// foreground slot goes empty, the background source (if any) is resumed.
  static void release(StopCallback stop) {
    final current = _currentStop;
    // Use `==` (not `identical`) because method tear-offs produce new
    // Function objects on each access but compare equal by (receiver, method).
    if (current == null || current != stop) return;
    _currentStop = null;
    final bg = _bg;
    if (bg != null) {
      // Fire-and-forget so existing sync call sites don't change signature.
      Future.sync(bg.resume).catchError((_) {});
    }
  }
}
