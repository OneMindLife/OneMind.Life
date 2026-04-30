import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'active_audio.dart';

/// Plays a looping background music track for chats that opt in via
/// `chats.background_audio_url`. The URL must point at the `chat-audio`
/// Supabase Storage bucket (enforced by a DB trigger).
///
/// The per-user on/off preference persists across sessions in
/// [SharedPreferences]. First-time visitors default to ON.
class BackgroundAudioService {
  static const String _prefsKey = 'background_audio_enabled';

  final SharedPreferences _prefs;

  /// Lazily constructed so tests and users that never open a music-enabled
  /// chat don't pay the cost of initializing the audio_session platform
  /// channel.
  AudioPlayer? _player;

  bool _enabled;
  bool _inActiveChat = false;

  /// The URL currently loaded (or about to be loaded) into the player.
  /// Used to skip re-loading when the user re-enters the same chat.
  String? _loadedUrl;

  /// The URL requested for the current chat session (set by [enterChat]).
  /// We remember it even when playback is paused so [setEnabled(true)] can
  /// resume without the screen having to re-announce the URL.
  String? _currentUrl;

  /// Handle registered with [ActiveAudio] so narration/video audio can
  /// temporarily pause this background track. Lifecycle: registered on
  /// [enterChat], cleared on [leaveChat].
  BackgroundAudioHandle? _arbiterHandle;

  /// Listens for app/tab lifecycle changes (browser tab hidden, OS suspend,
  /// etc.) so we pause playback while the user can't hear it anyway, and
  /// resume on return. Web browsers vary on whether they auto-pause hidden
  /// `<audio>` elements — handling it ourselves makes behavior consistent.
  AppLifecycleListener? _lifecycleListener;

  /// True when the lifecycle listener paused playback. Used so we only
  /// auto-resume on return if WE were the ones who paused (not, say, the
  /// user toggling the music off mid-background).
  bool _pausedByLifecycle = false;

  BackgroundAudioService(this._prefs)
      : _enabled = _prefs.getBool(_prefsKey) ?? true {
    _lifecycleListener = AppLifecycleListener(
      onHide: _onAppBackground,
      onPause: _onAppBackground,
      onInactive: _onAppBackground,
      onShow: _onAppForeground,
      onResume: _onAppForeground,
    );
  }

  Future<void> _onAppBackground() async {
    final player = _player;
    if (player == null || !player.playing) return;
    _pausedByLifecycle = true;
    await player.pause();
  }

  Future<void> _onAppForeground() async {
    if (!_pausedByLifecycle) return;
    _pausedByLifecycle = false;
    if (_enabled && _inActiveChat && _currentUrl != null) {
      await _startPlayback(_currentUrl!);
    }
  }

  bool get isEnabled => _enabled;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _prefs.setBool(_prefsKey, enabled);
    if (_inActiveChat && _currentUrl != null) {
      if (enabled) {
        await _startPlayback(_currentUrl!);
      } else {
        await _player?.pause();
      }
    }
  }

  /// Called when the user opens a chat that has a background audio URL.
  /// Pass the chat's `background_audio_url`.
  Future<void> enterChat(String url) async {
    _inActiveChat = true;
    _currentUrl = url;
    _registerWithArbiter();
    if (_enabled) await _startPlayback(url);
  }

  /// Called when the user leaves the chat. Fully stops playback and
  /// rewinds the player so a future re-entry starts fresh rather than
  /// briefly resuming from the previous offset before `enterChat` runs.
  Future<void> leaveChat() async {
    _inActiveChat = false;
    _currentUrl = null;
    _unregisterWithArbiter();
    final player = _player;
    if (player != null) {
      await player.stop();
      // stop() leaves the source loaded; force a re-setUrl on next enter.
      _loadedUrl = null;
    }
  }

  void _registerWithArbiter() {
    if (_arbiterHandle != null) return;
    _arbiterHandle = BackgroundAudioHandle(
      // Narration/video claimed audio — duck out.
      pause: () async {
        final p = _player;
        if (p != null && p.playing) await p.pause();
      },
      // Foreground finished — come back if the user still wants the music
      // and we're still sitting in a music-enabled chat.
      resume: () async {
        if (_enabled && _inActiveChat && _currentUrl != null) {
          await _startPlayback(_currentUrl!);
        }
      },
    );
    ActiveAudio.registerBackground(_arbiterHandle!);
  }

  void _unregisterWithArbiter() {
    final h = _arbiterHandle;
    if (h == null) return;
    ActiveAudio.unregisterBackground(h);
    _arbiterHandle = null;
  }

  Future<void> _startPlayback(String url) async {
    try {
      final player = _player ??= AudioPlayer();
      if (_loadedUrl != url) {
        await player.setUrl(url);
        await player.setLoopMode(LoopMode.one);
        await player.setVolume(0.5);
        _loadedUrl = url;
      }
      // Don't start over a foreground source — the arbiter's resume
      // callback will bring us back in when it finishes.
      if (!player.playing && !ActiveAudio.isForegroundActive) {
        await player.play();
      }
    } catch (_) {
      // Swallow playback errors silently — background music is a
      // best-effort enhancement and should never break the chat UI.
    }
  }

  Future<void> dispose() async {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await _player?.dispose();
    _player = null;
  }
}
