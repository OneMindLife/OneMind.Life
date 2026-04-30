import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../providers/providers.dart';
import '../services/active_audio.dart';

/// Play the convergence text aloud.
///
/// If [audioUrl] is provided, plays the pre-recorded ElevenLabs narration
/// via just_audio. Otherwise falls back to on-device TTS (flutter_tts).
class TtsButton extends ConsumerStatefulWidget {
  final String text;
  final String? audioUrl;
  final double size;
  final Color? color;

  /// Analytics context. When chatId + source are both provided, tapping the
  /// button logs a `chat_audio_played` event.
  final String? chatId;

  /// `'initial_message'` or `'cycle_winner'`. Required if chatId is set.
  final String? source;

  /// Cycle ID (only set when source == 'cycle_winner').
  final int? cycleId;

  const TtsButton({
    super.key,
    required this.text,
    this.audioUrl,
    this.size = 20,
    this.color,
    this.chatId,
    this.source,
    this.cycleId,
  });

  @override
  ConsumerState<TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends ConsumerState<TtsButton> {
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  StreamSubscription<ja.PlayerState>? _playerStateSub;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing =
          state.playing && state.processingState != ja.ProcessingState.completed;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
      if (state.processingState == ja.ProcessingState.completed) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.stop();
        // Hand the audio slot back so background music can resume.
        ActiveAudio.release(_stop);
      }
    });

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isPlaying = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
      ActiveAudio.release(_stop);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isPlaying = false);
      ActiveAudio.release(_stop);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isPlaying = false);
      ActiveAudio.release(_stop);
    });
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    _tts.setVolume(1.0);
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _stop();
      return;
    }
    // Stop any other audio (TTS or video audio) that's currently active.
    await ActiveAudio.claim(_stop);
    if (widget.audioUrl != null) {
      try {
        await _audioPlayer.setUrl(widget.audioUrl!);
        await _audioPlayer.play();
        _logPlayed(hasPreRecorded: true);
        return;
      } catch (_) {
        // Fall through to device TTS if the URL fails.
      }
    }
    await _tts.speak(widget.text);
    _logPlayed(hasPreRecorded: false);
  }

  void _logPlayed({required bool hasPreRecorded}) {
    final chatId = widget.chatId;
    final source = widget.source;
    if (chatId == null || source == null) return;
    ref.read(analyticsServiceProvider).logChatAudioPlayed(
          chatId: chatId,
          source: source,
          cycleId: widget.cycleId,
          hasPreRecorded: hasPreRecorded,
        );
  }

  Future<void> _stop() async {
    ActiveAudio.release(_stop);
    await _audioPlayer.stop();
    await _tts.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  @override
  void dispose() {
    ActiveAudio.release(_stop);
    _playerStateSub?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: widget.size + 16,
        height: widget.size + 16,
      ),
      tooltip: _isPlaying ? 'Stop' : 'Read aloud',
      onPressed: _toggle,
      icon: Icon(
        _isPlaying ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
        size: widget.size,
        color: color,
      ),
    );
  }
}
