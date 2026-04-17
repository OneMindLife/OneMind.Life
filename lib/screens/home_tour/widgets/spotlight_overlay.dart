import 'dart:async';
import 'dart:convert';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import 'package:flutter/services.dart';

/// Shared TTS state across all tutorial/home tour dialogs.
/// Uses just_audio which handles web Audio API and autoplay policy properly.
class TutorialTts {
  TutorialTts._();

  static final _audioPlayer = ja.AudioPlayer();
  static bool _initialized = false;
  static StreamSubscription<ja.PlayerState>? _completeSubscription;

  /// Current word timings for the playing audio (null if using TTS fallback).
  static List<Map<String, dynamic>>? currentTimings;
  /// Notifier for playback position (seconds). Widgets listen to animate text.
  static final playbackPosition = ValueNotifier<double>(0.0);
  static Timer? _positionTimer;
  /// Muted state persists across dialogs. Starts unmuted.
  static bool muted = false;
  /// Generation counter to invalidate stale completion handlers.
  static int _generation = 0;

  /// Check if pre-recorded audio exists for this text.
  static bool hasAudio(String text) {
    final clean = _cleanForSpeech(text);
    return _audioAssets.containsKey(clean);
  }

  /// Get cached word timings for a description (if preloaded).
  /// Used to pre-set timings before speak() is called, preventing
  /// the first-frame flash where text renders without timings.
  static List<Map<String, dynamic>>? getCachedTimings(String text) {
    final clean = _cleanForSpeech(text);
    final assetPath = _audioAssets[clean];
    if (assetPath == null) return null;
    return _timingsCache[assetPath];
  }

  /// Pre-recorded audio assets keyed by cleaned TTS text.
  static const _audioAssets = <String, String>{
    // Chat tour
    "This is a OneMind chat. You'll see how ideas compete until the group reaches a decision. Let's walk through how it works.": 'audio/tutorial/chat_tour_intro.mp3',
    'This is the chat name.': 'audio/tutorial/chat_tour_title.mp3',
    'This is the discussion topic. Everyone submits their idea in response.': 'audio/tutorial/chat_tour_message.mp3',
    'This is where the chosen idea will go.': 'audio/tutorial/chat_tour_placeholder.mp3',
    "The chat hasn't started yet, so it's empty for now.": 'audio/tutorial/chat_tour_placeholder2.mp3',
    'This shows which round the chat is in. The group goes through multiple rounds to choose the winning idea.': 'audio/tutorial/chat_tour_round.mp3',
    'Each round has two phases: Proposing and Rating.': 'audio/tutorial/chat_tour_phases1.mp3',
    'Each round starts in the Proposing phase.': 'audio/tutorial/chat_tour_phases2.mp3',
    "This is the participation bar. It tracks the group's progress in the current phase.": 'audio/tutorial/chat_tour_progress1.mp3',
    'Once it reaches 100%, the chat moves on to the next phase.': 'audio/tutorial/chat_tour_progress2.mp3',
    'Tap the leaderboard button to see the leaderboard.': 'audio/tutorial/chat_tour_participants.mp3',
    "Each phase has a time limit — when it runs out, the chat moves on.": 'audio/tutorial/chat_tour_timer.mp3',
    'Type your best idea here to replace the placeholder above.': 'audio/tutorial/chat_tour_submit.mp3',
    // Leaderboard overlay
    'These are the participants in the chat. You, Alex, Sam, and Jordan.': 'audio/tutorial/leaderboard_participants.mp3',
    'These are the user rankings. Everyone is ranked based on their performance in the Proposing and Rating phases across all rounds.': 'audio/tutorial/leaderboard_rankings.mp3',
    'No rounds have been completed yet, so everyone starts unranked.': 'audio/tutorial/leaderboard_unranked.mp3',
    'Alex, Sam, and Jordan have already submitted their ideas for this Proposing phase.': 'audio/tutorial/leaderboard_submitted.mp3',
    'The better the idea, the higher the rank.': 'audio/tutorial/leaderboard_rank.mp3',
    'Tap the X to close the leaderboard.': 'audio/tutorial/leaderboard_close.mp3',
    // R1 rating
    'Now that everyone has submitted their ideas, the rating phase begins.': 'audio/tutorial/r1_rating_phase.mp3',
    "Click Start Rating below to start rating everyone's ideas.": 'audio/tutorial/r1_rating_button.mp3',
    "This is the rating screen. You won't rate your own idea — only other people's.": 'audio/tutorial/rating_intro.mp3',
    "The closer your ratings match the group's, the higher you rank.": 'audio/tutorial/rating_rank.mp3',
    'The top idea scores higher. Tap swap to put your preferred idea on top, then tap confirm to lock it in.': 'audio/tutorial/rating_binary.mp3',
    'Place each idea on the scale. Use up down to move, then tap confirm to lock it in. Press undo to redo your previous placement.': 'audio/tutorial/rating_positioning.mp3',
    // R1 results
    'Everyone has rated. "Movie Night" won! It is now the new placeholder.': 'audio/tutorial/r1_result_winner.mp3',
    'Tap it to continue.': 'audio/tutorial/r1_result_tap.mp3',
    'This shows all completed round winners. Only 1 round has been completed so far.': 'audio/tutorial/r1_cycle_explain.mp3',
    'Tap it to view the full rating results.': 'audio/tutorial/r1_cycle_tap.mp3',
    "These are the group's combined rating results.": 'audio/tutorial/results_winner.mp3',
    'When done viewing the results, press the back arrow to continue.': 'audio/tutorial/results_back.mp3',
    'Press the back arrow to continue.': 'audio/tutorial/r1_cycle_back.mp3',
    // R1 leaderboard
    'Tap the leaderboard button to continue.': 'audio/tutorial/r1_leaderboard_tap.mp3',
    'The leaderboard has been updated.': 'audio/tutorial/r1_leaderboard_updated.mp3',
    'Press the X to continue.': 'audio/tutorial/r1_leaderboard_done.mp3',
    // R2
    'Round 2 begins now.': 'audio/tutorial/r2_new_round.mp3',
    'Try to replace "Movie Night". Send your best idea!': 'audio/tutorial/r2_replace.mp3',
    '"Movie Night" is the previous round\'s winner. If it also wins this round, it gets placed permanently in the chat.': 'audio/tutorial/r2_carried_winner.mp3',
    'Your idea won! It is now the new placeholder.': 'audio/tutorial/r2_result_won.mp3',
    'Now there are 2 completed rounds.': 'audio/tutorial/r2_cycle_explain.mp3',
    'Tap the Round 2 winner to view the full rating results.': 'audio/tutorial/r2_cycle_tap.mp3',
    '"Movie Night" lost this round, so it was replaced by the new winner — your idea.': 'audio/tutorial/r2_results_explain.mp3',
    // R3
    'Now time for Round 3.': 'audio/tutorial/r3_new_round.mp3',
    "Can you think of something better? Type your best idea and submit it! If you can't think of anything, tap the skip button to skip.": 'audio/tutorial/r3_replace.mp3',
    // Convergence
    'Your idea won again, so it is added permanently to the chat.': 'audio/tutorial/convergence_won.mp3',
    "See how the same idea won Round 2 and Round 3? That's called convergence — the group has converged on an idea.": 'audio/tutorial/cycle_convergence.mp3',
    // cycle_back shares same audio as r1_cycle_back (same text after cleaning)
    // 'Press the back arrow to continue.' already mapped via r1_cycle_back
    // Post-tutorial
    'Now the group works toward its next convergence.': 'audio/tutorial/process_continues.mp3',
    'Share this link, QR code, or invite code for others to join your chat.': 'audio/tutorial/share.mp3',
    'Tap the share button to continue.': 'audio/tutorial/share_tap.mp3',
    // 'Press the X to continue.' already mapped via r1_leaderboard_done
    // Home tour
    'This is your display name.': 'audio/tutorial/home_display_name.mp3',
    'Filter your chats by name.': 'audio/tutorial/home_search.mp3',
    "These are chats you're waiting to be accepted into.": 'audio/tutorial/home_pending.mp3',
    'These are the chats that you are in.': 'audio/tutorial/home_your_chats.mp3',
    'Tap to create a chat, join an existing one, or discover public chats.': 'audio/tutorial/home_create.mp3',
    'Tap here to switch the app language.': 'audio/tutorial/home_language.mp3',
    'Replay the tutorial to learn how OneMind works.': 'audio/tutorial/home_how_it_works.mp3',
    'Contact us, view the source code, or read the legal documents.': 'audio/tutorial/home_legal.mp3',
  };

  /// Cache of preloaded word timings keyed by asset path.
  static final _timingsCache = <String, List<Map<String, dynamic>>>{};

  /// Preload all word timing JSONs and the first audio asset.
  /// Call early (e.g. tutorial initState) so everything is cached
  /// before the first dialog appears.
  static Future<void> preload() async {
    if (_initialized) return;
    _initialized = true;
    for (final assetPath in _audioAssets.values) {
      final jsonPath = assetPath.replaceAll('.mp3', '.json');
      try {
        final jsonStr = await rootBundle.loadString('assets/$jsonPath');
        _timingsCache[assetPath] = List<Map<String, dynamic>>.from(json.decode(jsonStr));
      } catch (_) {}
    }
    // Pre-set the first audio source so setAsset() is instant for dialog 1
    const firstAsset = 'audio/tutorial/chat_tour_title.mp3';
    try {
      await _audioPlayer.setAsset('assets/$firstAsset');
    } catch (_) {}
  }

  static Future<void> _ensureInit() => preload();

  /// Replace [markers] with spoken names for TTS.
  static String _cleanForSpeech(String text) {
    return text
        .replaceAll('[back]', 'the back arrow')
        .replaceAll('[skip]', 'the skip button')
        .replaceAll('[leaderboard]', 'the leaderboard button')
        .replaceAll('[people]', 'the people button')
        .replaceAll('[swap]', 'swap')
        .replaceAll('[check]', 'confirm')
        .replaceAll('[up]', 'up')
        .replaceAll('[down]', 'down')
        .replaceAll('[undo]', 'undo')
        .replaceAll('[proposing]', 'Proposing')
        .replaceAll('[rating]', 'Rating')
        .replaceAll('[startRating]', 'Start Rating')
        .replaceAll(RegExp(r'\[.*?\]'), '') // catch any remaining
        .replaceAll('  ', ' ')
        .trim();
  }

  static Future<void> speak(String text, {VoidCallback? onComplete}) async {
    await _ensureInit();
    if (muted) return;
    // Cancel any in-progress speech/audio first
    _generation++;
    _positionTimer?.cancel();
    playbackPosition.value = 0.0; // Reset so new dialog text starts invisible
    currentTimings = null;
    await _audioPlayer.stop();
    final gen = _generation;
    final clean = _cleanForSpeech(text);

    // Check for pre-recorded audio asset
    final assetPath = _audioAssets[clean];
    if (assetPath != null) {
      // Use preloaded word timings (loaded in _ensureInit)
      currentTimings = _timingsCache[assetPath];
      playbackPosition.value = 0.0;

      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ja.ProcessingState.completed) {
          _positionTimer?.cancel();
          if (gen == _generation) onComplete?.call();
        }
      });

      try {
        await _audioPlayer.setAsset('assets/$assetPath');
      } on ja.PlayerInterruptedException {
        return; // Loading interrupted by another play/stop call
      }
      if (gen != _generation) return; // Stale after async gap
      _audioPlayer.play();

      // Track playback position for word-by-word reveal
      _positionTimer?.cancel();
      _positionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (gen != _generation) {
          _positionTimer?.cancel();
          return;
        }
        final pos = _audioPlayer.position;
        playbackPosition.value = pos.inMilliseconds / 1000.0;
      });
      return;
    }

    // No pre-recorded audio — treat as if muted for this dialog.
    // The button will show so the user can advance manually.
  }

  static DateTime _lastStopTime = DateTime(2000);

  static Future<void> stop([String caller = 'unknown']) async {
    _generation++; // Invalidate pending completion handlers
    _positionTimer?.cancel();
    currentTimings = null;
    playbackPosition.value = 0.0; // Reset so next dialog starts invisible
    _completeSubscription?.cancel();
    _completeSubscription = null;
    _lastStopTime = DateTime.now();
    await _audioPlayer.stop();
  }

  static Future<void> replay(String text, {VoidCallback? onComplete}) async {
    await _ensureInit();
    _generation++;
    await _audioPlayer.stop();
    final gen = _generation;
    final clean = _cleanForSpeech(text);

    // Check for pre-recorded audio
    final assetPath = _audioAssets[clean];
    if (assetPath != null) {
      _completeSubscription?.cancel();
      _completeSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ja.ProcessingState.completed) {
          if (gen == _generation) onComplete?.call();
        }
      });
      try {
        await _audioPlayer.setAsset('assets/$assetPath');
      } on ja.PlayerInterruptedException {
        return;
      }
      if (gen != _generation) return;
      _audioPlayer.play();
      return;
    }

    // No audio file — nothing to replay
  }
}

/// A tooltip card shown during the home tour and tutorial.
/// Displays title, description, Next button, and TTS mute/replay button.
/// Auto-speaks description when shown (unless muted).
class TourTooltipCard extends StatefulWidget {
  final String title;
  final String description;
  final Widget? descriptionWidget;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final int stepIndex;
  final int totalSteps;
  final String nextLabel;
  final String skipLabel;
  final String stepOfLabel;
  final bool autoAdvance;
  /// When true, description changes don't reset timed text or audio.
  /// Used for sub-step transitions where the tooltip stays visible.
  final bool skipResetOnDescriptionChange;
  const TourTooltipCard({
    super.key,
    required this.title,
    required this.description,
    this.descriptionWidget,
    required this.onNext,
    required this.onSkip,
    required this.stepIndex,
    required this.totalSteps,
    required this.nextLabel,
    required this.skipLabel,
    required this.stepOfLabel,
    this.autoAdvance = true,
    this.skipResetOnDescriptionChange = false,
  });

  @override
  State<TourTooltipCard> createState() => _TourTooltipCardState();
}

enum _TtsState { playing, done, muted }

class _TourTooltipCardState extends State<TourTooltipCard> {
  _TtsState _state = _TtsState.muted;
  Timer? _speakTimer;

  String? _lastSpokenText;

  @override
  void initState() {
    super.initState();
    _state = TutorialTts.muted ? _TtsState.muted : _TtsState.playing;
    // Pre-set timings from cache so first frame renders correctly (no flash)
    TutorialTts.currentTimings = TutorialTts.getCachedTimings(widget.description);
    TutorialTts.playbackPosition.value = 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _autoSpeak();
      }
    });
  }

  @override
  void dispose() {
    _speakTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(TourTooltipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.description != oldWidget.description) {
      _lastSpokenText = null;
      if (widget.skipResetOnDescriptionChange) {
        // Sub-step transition: tooltip stays visible, don't reset timed text.
        if (!TutorialTts.muted) {
          setState(() => _state = _TtsState.playing);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoSpeak();
          });
        }
        return;
      }
      // Normal step transition: tooltip is fading out → element reveals (600ms)
      // → tooltip fades in (500ms). Start audio when fade-in begins so it
      // syncs with the tooltip appearing.
      if (!TutorialTts.muted) {
        TutorialTts.currentTimings = TutorialTts.getCachedTimings(widget.description);
        TutorialTts.playbackPosition.value = 0.0;
        setState(() => _state = _TtsState.playing);
        _speakTimer?.cancel();
        _speakTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted) {
            _autoSpeak();
          }
        });
      }
    }
  }

  void _autoSpeak() {
    if (TutorialTts.muted) return;
    if (widget.description.isEmpty) return;
    if (_lastSpokenText == widget.description) return;
    _lastSpokenText = widget.description;
    // No audio file → treat as muted for this dialog (show button)
    if (!TutorialTts.hasAudio(widget.description)) {
      setState(() => _state = _TtsState.done);
      return;
    }
    setState(() => _state = _TtsState.playing);
    TutorialTts.speak(widget.description, onComplete: _onSpeechDone);
  }

  void _onSpeechDone() {
    if (mounted && !TutorialTts.muted && widget.autoAdvance) {
      widget.onNext();
    } else if (mounted && !TutorialTts.muted) {
      setState(() => _state = _TtsState.done);
    }
  }

  void _toggleMute() {
    if (TutorialTts.muted) {
      // Unmute → start speaking
      TutorialTts.muted = false;
      setState(() => _state = _TtsState.playing);
      TutorialTts.speak(widget.description, onComplete: _onSpeechDone);
    } else {
      // Mute → stop
      TutorialTts.muted = true;
      TutorialTts.stop();
      setState(() => _state = _TtsState.muted);
    }
  }

  void _replay() {
    setState(() => _state = _TtsState.playing);
    TutorialTts.replay(widget.description, onComplete: _onSpeechDone);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final IconData icon;
    final VoidCallback onPressed;
    switch (_state) {
      case _TtsState.playing:
        icon = Icons.volume_up;
        onPressed = _toggleMute;
      case _TtsState.done:
        icon = Icons.replay;
        onPressed = _replay;
      case _TtsState.muted:
        icon = Icons.volume_off;
        onPressed = _toggleMute;
    }

    return Material(
      elevation: 8,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with TTS button on right
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: Icon(icon, size: 20),
                  onPressed: onPressed,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Show plain text when no audio file exists (state goes straight to done)
            _state == _TtsState.done && !TutorialTts.hasAudio(widget.description)
                ? (widget.descriptionWidget ?? Text(
                    widget.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ))
                : _TimedTextWidget(description: widget.description),
            // Hide button while audio is playing and will auto-advance
            if (!(_state == _TtsState.playing && widget.autoAdvance)) ...[
              const SizedBox(height: 12),
              // Next button right-aligned
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () {
                      TutorialTts.stop();
                      widget.onNext();
                    },
                    child: Text(widget.nextLabel),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tooltip card without a Next button, but with TTS mute toggle.
/// Used for action hints where the user taps an element instead of Next.
/// Auto-speaks on creation if unmuted.
class NoButtonTtsCard extends StatefulWidget {
  final String title;
  final String description;
  final Widget? descriptionWidget;

  const NoButtonTtsCard({
    super.key,
    required this.title,
    required this.description,
    this.descriptionWidget,
  });

  @override
  State<NoButtonTtsCard> createState() => _NoButtonTtsCardState();
}

class _NoButtonTtsCardState extends State<NoButtonTtsCard> {
  @override
  void initState() {
    super.initState();
    // Pre-set timings from cache so first frame renders correctly (no flash)
    TutorialTts.currentTimings = TutorialTts.getCachedTimings(widget.description);
    TutorialTts.playbackPosition.value = 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !TutorialTts.muted && widget.description.isNotEmpty) {
        TutorialTts.speak(widget.description);
      }
    });
  }

  @override
  void dispose() {
    // Don't stop TTS here — races with the next card's speak()
    // TTS is stopped explicitly by Next button, mute toggle, and page navigation
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                StatefulBuilder(
                  builder: (context, setLocalState) => IconButton(
                    icon: Icon(
                      TutorialTts.muted ? Icons.volume_off : Icons.volume_up,
                      size: 20,
                    ),
                    onPressed: () {
                      if (TutorialTts.muted) {
                        TutorialTts.muted = false;
                        TutorialTts.speak(widget.description);
                      } else {
                        TutorialTts.muted = true;
                        TutorialTts.stop();
                      }
                      setLocalState(() {});
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            !TutorialTts.muted
                ? _TimedTextWidget(description: widget.description)
                : (widget.descriptionWidget ??
                    Text(
                      widget.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    )),
          ],
        ),
      ),
    );
  }
}

/// Shared widget that renders text word-by-word synced to audio playback.
class _TimedTextWidget extends StatelessWidget {
  final String description;
  const _TimedTextWidget({required this.description});

  static final _phaseWords = <String, Widget Function(BuildContext)>{
    'Proposing': (ctx) => _chip(ctx, 'Proposing', AppColors.proposing),
    'Rating.': (ctx) => _chip(ctx, 'Rating', AppColors.rating),
    'Rating': (ctx) => _chip(ctx, 'Rating', AppColors.rating),
  };

  /// Map of timing words → inline icon builders for control buttons
  /// Includes both marker names ([check]) and spoken equivalents (confirm)
  static final _controlIcons = <String, Widget Function(BuildContext)>{
    'swap': (ctx) => _controlIcon(ctx, Icons.swap_vert, isOutlined: true),
    'check': (ctx) => _controlIcon(ctx, Icons.check, isFilled: true),
    'confirm': (ctx) => _controlIcon(ctx, Icons.check, isFilled: true),
    'up': (ctx) => _controlIcon(ctx, Icons.arrow_upward, isOutlined: true),
    'down': (ctx) => _controlIcon(ctx, Icons.arrow_downward, isOutlined: true),
    'undo': (ctx) => _controlIcon(ctx, Icons.undo, isOutlined: true, isUndo: true),
  };

  static Widget _controlIcon(BuildContext ctx, IconData icon,
      {bool isOutlined = false, bool isFilled = false, bool isUndo = false}) {
    final primary = Theme.of(ctx).colorScheme.primary;
    final undoColor = const Color(0xFFEF5350).withAlpha(128);
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isFilled ? primary : Theme.of(ctx).colorScheme.surface,
        shape: BoxShape.circle,
        border: isFilled ? null : Border.all(
          color: isUndo ? undoColor : primary, width: 2),
      ),
      child: Icon(icon, size: 18,
          color: isFilled ? Colors.white : (isUndo ? undoColor : primary)),
    );
  }

  static Widget _chip(BuildContext ctx, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
        color: Colors.white, fontWeight: FontWeight.bold,
      )),
    );
  }

  /// Fallback text with inline widgets (no timing, full text visible)
  Widget _buildFallbackWithWidgets(BuildContext context, TextStyle style, {bool firstSentenceOnly = false}) {
    final hasPhase = description.contains('Proposing') && description.contains('phase') ||
        description.contains('[proposing]') || description.contains('[rating]');
    final hasStart = description.contains('Start Rating') && description.contains('Click');
    final hasCtrl = description.contains('[swap]') || description.contains('[check]') ||
        description.contains('[up]') || description.contains('[undo]');
    final hasBack = description.contains('[back]');
    final hasSkip = description.contains('[skip]');
    final hasLb = description.contains('[leaderboard]') || description.contains('leaderboard button');
    final usedControls = <String>{};
    var skipNextRating = false;

    var desc = description;
    if (firstSentenceOnly) {
      final match = RegExp(r'[.!?]\s').firstMatch(desc);
      if (match != null) desc = desc.substring(0, match.end).trim();
    }
    final words = desc.split(' ');
    final spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];

      // Skip "Rating" consumed by Start Rating button
      if (skipNextRating && word == 'Rating') {
        skipNextRating = false;
        continue;
      }

      // Start Rating button
      if (hasStart && word == 'Start' && i + 1 < words.length && words[i + 1].startsWith('Rating') && !usedControls.contains('startRating')) {
        usedControls.add('startRating');
        skipNextRating = true;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AbsorbPointer(
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.how_to_vote_outlined, size: 20),
                label: const Text('Start Rating'),
              ),
            ),
          ),
        ));
        spans.add(const TextSpan(text: ' '));
        continue;
      }

      // Phase chips
      if (hasPhase) {
        final builder = _phaseWords[word] ?? _phaseWords[word.replaceAll('.', '')];
        if (builder != null) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: builder(context),
            ),
          ));
          if (!word.endsWith('.') && !word.endsWith(',')) {
            spans.add(const TextSpan(text: ' '));
          }
          continue;
        }
      }

      // Control icons
      if (hasCtrl) {
        final wordLower = word.toLowerCase().replaceAll('.', '').replaceAll('[', '').replaceAll(']', '');
        final controlBuilder = _controlIcons[wordLower];
        if (controlBuilder != null && !usedControls.contains(wordLower)) {
          usedControls.add(wordLower);
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: controlBuilder(context),
            ),
          ));
          spans.add(const TextSpan(text: ' '));
          continue;
        }
      }

      // Leaderboard icon — first occurrence only
      if (hasLb && (word == '[leaderboard]' || (word.toLowerCase().replaceAll('.', '') == 'leaderboard' && !usedControls.contains('leaderboard')))) {
        usedControls.add('leaderboard');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(Icons.leaderboard, size: 18,
                color: Theme.of(context).colorScheme.onSurface),
          ),
        ));
        spans.add(const TextSpan(text: ' '));
        continue;
      }

      // Back arrow icon
      if (hasBack && word == '[back]') {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(Icons.arrow_back, size: 18,
                color: Theme.of(context).colorScheme.onSurface),
          ),
        ));
        spans.add(const TextSpan(text: ' '));
        continue;
      }

      // Skip button
      if (hasSkip && word == '[skip]') {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: AbsorbPointer(
            child: SizedBox(
              width: 36,
              height: 36,
              child: IconButton.filled(
                onPressed: () {},
                icon: const Icon(Icons.skip_next, size: 22),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ));
        spans.add(const TextSpan(text: ' '));
        continue;
      }

      spans.add(TextSpan(text: '$word ', style: style));
    }
    return Text.rich(TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    // Detect phase chips — check both marker format and cleaned text
    final hasPhaseMarkers = description.contains('[proposing]') ||
        description.contains('[rating]') ||
        (description.contains('Proposing') && description.contains('phase'));
    final hasLeaderboard = description.contains('[leaderboard]') ||
        description.contains('leaderboard button');
    final hasControls = description.contains('[swap]') ||
        description.contains('[check]') ||
        description.contains('[up]') ||
        description.contains('[undo]');
    final hasStartRating = description.contains('Start Rating') &&
        description.contains('Click');
    return ValueListenableBuilder<double>(
      valueListenable: TutorialTts.playbackPosition,
      builder: (context, position, _) {
        final timings = TutorialTts.currentTimings;
        if (timings == null || timings.isEmpty) {
          if (!TutorialTts.muted && position == 0) {
            // Audio expected but not started — timings pre-set from cache
            // so word-by-word will work on next frame. Show nothing (timings
            // handle reveal). If no timings cached, show full text as fallback.
            if (hasPhaseMarkers || hasStartRating || hasControls || hasLeaderboard || description.contains('[back]') || description.contains('[skip]')) {
              return Opacity(opacity: 0, child: _buildFallbackWithWidgets(context, style));
            }
            return Text(description, style: style.copyWith(
              color: style.color?.withValues(alpha: 0),
            ));
          }
          // Muted or audio done — show full text with widgets
          if (hasPhaseMarkers || hasStartRating || hasControls || hasLeaderboard || description.contains('[back]') || description.contains('[skip]')) {
            return _buildFallbackWithWidgets(context, style);
          }
          return Text(description, style: style);
        }
        // Group words into sentences (split on . ! ?)
        final sentences = <List<Map<String, dynamic>>>[];
        var currentSentence = <Map<String, dynamic>>[];
        for (final w in timings) {
          currentSentence.add(w);
          final word = w['word'] as String;
          if (word.endsWith('.') || word.endsWith('!') || word.endsWith('?')) {
            sentences.add(currentSentence);
            currentSentence = [];
          }
        }
        if (currentSentence.isNotEmpty) sentences.add(currentSentence);

        // Track which control words have been replaced (only first occurrence)
        final usedControls = <String>{};
        var skipNextRating = false; // Skip "Rating" after "Start" button render

        var isFirstSentence = true;
        return Text.rich(
          TextSpan(
            children: sentences.expand((sentence) {
              // Fade based on first word of sentence
              final sentenceStart = (sentence.first['start'] as num).toDouble();
              final fadeStart = sentenceStart - 0.4;
              double op;
              if (isFirstSentence) {
                // First sentence always visible to prevent jitter when
                // timings load but playback position is still 0
                op = 1.0;
                isFirstSentence = false;
              } else if (position >= sentenceStart) {
                op = 1.0;
              } else if (position >= fadeStart) {
                op = (position - fadeStart) / (sentenceStart - fadeStart);
              } else {
                op = 0.0;
              }
              op = op.clamp(0.0, 1.0);

              return sentence.map((w) {
                final word = w['word'] as String;

                // Skip "Rating" that was already consumed by Start Rating button
                if (skipNextRating && word == 'Rating') {
                  skipNextRating = false;
                  return const TextSpan(text: ''); // empty, button already rendered
                }

                // Render "Start Rating" as inline button
                if (hasStartRating && word == 'Start' && !usedControls.contains('startRating')) {
                  usedControls.add('startRating');
                  skipNextRating = true;
                  return WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Opacity(
                        opacity: op,
                        child: AbsorbPointer(
                          child: FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.how_to_vote_outlined, size: 20),
                            label: const Text('Start Rating'),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (hasPhaseMarkers) {
                  final builder = _phaseWords[word];
                  if (builder != null) {
                    return WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Opacity(opacity: op, child: builder(context)),
                      ),
                    );
                  }
                }
                if (hasLeaderboard && word.toLowerCase().replaceAll('.', '') == 'leaderboard' && !usedControls.contains('leaderboard')) {
                  usedControls.add('leaderboard');
                  return WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Opacity(
                        opacity: op,
                        child: Icon(Icons.leaderboard, size: 18,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  );
                }
                if (hasControls) {
                  final wordLower = word.toLowerCase().replaceAll('.', '').replaceAll('[', '').replaceAll(']', '');
                  final controlBuilder = _controlIcons[wordLower];
                  if (controlBuilder != null && !usedControls.contains(wordLower)) {
                    usedControls.add(wordLower);
                    return WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Opacity(opacity: op, child: controlBuilder(context)),
                      ),
                    );
                  }
                }

                // Skip button — replace first "skip" with button widget
                if (description.contains('[skip]') && word.toLowerCase().replaceAll('.', '').replaceAll(',', '') == 'skip' && !usedControls.contains('skip')) {
                  usedControls.add('skip');
                  return WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Opacity(
                        opacity: op,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton.filled(
                            onPressed: () {},
                            icon: const Icon(Icons.skip_next, size: 22),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // Back arrow icon — replace "back" with icon, skip "arrow"
                if (description.contains('[back]') && word.toLowerCase() == 'back') {
                  return WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Opacity(
                        opacity: op,
                        child: Icon(Icons.arrow_back, size: 18,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  );
                }
                if (description.contains('[back]') && word.toLowerCase() == 'arrow') {
                  return const TextSpan(text: '') as InlineSpan;
                }

                return TextSpan(
                  text: '$word ',
                  style: style.copyWith(
                    color: style.color?.withValues(alpha: op),
                  ),
                ) as InlineSpan;
              });
            }).toList(),
          ),
        );
      },
    );
  }
}
