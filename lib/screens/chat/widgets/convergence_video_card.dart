import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../config/app_colors.dart';
import '../../../providers/providers.dart';
import '../../../services/active_audio.dart';
import '../../../services/analytics_service.dart';
import '../../../services/remote_log_service.dart';

class ConvergenceVideoCard extends ConsumerStatefulWidget {
  final String videoUrl;

  /// Analytics context. Omit to disable analytics for this instance.
  final String? chatId;

  /// `'initial_message'` or `'cycle_winner'`. Required if chatId is set.
  final String? source;

  /// Cycle ID (only set when source == 'cycle_winner').
  final int? cycleId;

  /// Color of the thin scrub bar under the video. Defaults to brand teal;
  /// pass [AppColors.consensus] when this card is rendered inside an
  /// orange consensus / previous-winner panel so the bar matches.
  final Color? scrubBarColor;

  const ConvergenceVideoCard({
    super.key,
    required this.videoUrl,
    this.chatId,
    this.source,
    this.cycleId,
    this.scrubBarColor,
  });

  @override
  ConsumerState<ConvergenceVideoCard> createState() =>
      _ConvergenceVideoCardState();
}

class _ConvergenceVideoCardState extends ConsumerState<ConvergenceVideoCard> {
  VideoPlayerController? _videoController;
  bool _initFailed = false;

  // One-shot flags so each event fires at most once per widget lifetime.
  bool _impressionLogged = false;
  bool _startedLogged = false;
  bool _unmutedLogged = false;
  bool _completedLogged = false;
  final Set<int> _progressMilestonesHit = {}; // 25 | 50 | 75
  bool _wasMuted = true;

  // Captured at initState so dispose() can log without touching ref —
  // calling ref.read after the widget is unmounted throws "Cannot use ref
  // after disposed", which then cascades into thousands of "deactivated
  // widget ancestor" exceptions during widget-tree finalization.
  AnalyticsService? _analyticsRef;

  AnalyticsService? get _analytics {
    if (widget.chatId == null || widget.source == null) return null;
    return _analyticsRef;
  }

  @override
  void initState() {
    super.initState();
    // Best-effort capture — analytics is non-essential. Tolerant of missing
    // ProviderScope (some test scaffolds don't provide one).
    try {
      _analyticsRef = ref.read(analyticsServiceProvider);
    } catch (_) {
      _analyticsRef = null;
    }
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    RemoteLog.log('video_card_init_start', widget.videoUrl, {
      'chat_id': widget.chatId,
      'source': widget.source,
      'cycle_id': widget.cycleId,
    });
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await controller.initialize();
      await controller.setVolume(0.0);

      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.addListener(_onVideoTick);
      // Autoplay on loop, silent. The custom teal progress bar below
      // the video is the only control surface.
      await controller.setLooping(true);
      await controller.play();

      setState(() => _videoController = controller);
    } catch (e, stack) {
      RemoteLog.log(
        'video_card_init_error',
        e.toString(),
        {
          'error_type': e.runtimeType.toString(),
          'video_url': widget.videoUrl,
          'chat_id': widget.chatId,
          'source': widget.source,
          'cycle_id': widget.cycleId,
          'stack': stack.toString().split('\n').take(8).join('\n'),
        },
      );
      if (mounted) setState(() => _initFailed = true);
    }
  }

  void _onVideoTick() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    final value = c.value;
    final duration = value.duration.inMilliseconds;
    if (duration <= 0) return;
    final position = value.position.inMilliseconds;
    final a = _analytics;

    if (!_startedLogged && value.isPlaying) {
      _startedLogged = true;
      a?.logChatVideoStarted(
        chatId: widget.chatId!,
        source: widget.source!,
        cycleId: widget.cycleId,
        autoplay: true,
        durationSeconds: duration / 1000.0,
      );
    }

    if (_wasMuted && value.volume > 0.0) {
      _wasMuted = false;
      // Claim single-audio focus — mutes any other video or stops narration.
      ActiveAudio.claim(_muteSelf);
      if (!_unmutedLogged) {
        _unmutedLogged = true;
        a?.logChatVideoUnmuted(
          chatId: widget.chatId!,
          source: widget.source!,
          cycleId: widget.cycleId,
          atSeconds: position / 1000.0,
        );
      }
    } else if (!_wasMuted && value.volume == 0.0) {
      _wasMuted = true;
      ActiveAudio.release(_muteSelf);
    }

    final percent = (position / duration) * 100;
    for (final milestone in const [25, 50, 75]) {
      if (percent >= milestone && !_progressMilestonesHit.contains(milestone)) {
        _progressMilestonesHit.add(milestone);
        a?.logChatVideoProgress(
          chatId: widget.chatId!,
          source: widget.source!,
          cycleId: widget.cycleId,
          percent: milestone,
        );
      }
    }

    if (!_completedLogged && position > 0 && position >= duration - 250) {
      _completedLogged = true;
      a?.logChatVideoCompleted(
        chatId: widget.chatId!,
        source: widget.source!,
        cycleId: widget.cycleId,
        durationSeconds: duration / 1000.0,
      );
    }

    // Rebuild so the teal progress bar under the video advances on each
    // playback tick. LinearProgressIndicator is cheap; we're already
    // getting one listener callback per frame from the controller.
    if (mounted) setState(() {});
  }

  void _logImpressionOnce() {
    if (_impressionLogged) return;
    _impressionLogged = true;
    _analytics?.logChatVideoImpression(
      chatId: widget.chatId!,
      source: widget.source!,
      cycleId: widget.cycleId,
    );
  }

  /// Mute this video's audio. Called by [ActiveAudio] when another source
  /// claims audio focus.
  Future<void> _muteSelf() async {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.volume == 0.0) return;
    await c.setVolume(0.0);
  }

  @override
  void dispose() {
    ActiveAudio.release(_muteSelf);
    _logAbandonedIfNeeded();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  void _logAbandonedIfNeeded() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    if (_completedLogged) return;
    if (!_startedLogged) return;
    final duration = c.value.duration.inMilliseconds;
    if (duration <= 0) return;
    final position = c.value.position.inMilliseconds;
    final percent = ((position / duration) * 100).clamp(0, 100).round();
    _analytics?.logChatVideoAbandoned(
      chatId: widget.chatId!,
      source: widget.source!,
      cycleId: widget.cycleId,
      watchTimeSeconds: position / 1000.0,
      percentWatched: percent,
      durationSeconds: duration / 1000.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initFailed) return const SizedBox.shrink();

    _logImpressionOnce();

    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final videoValue = controller.value;
    final durationMs = videoValue.duration.inMilliseconds;
    final positionMs = videoValue.position.inMilliseconds;
    final progress = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: videoValue.aspectRatio,
          child: VideoPlayer(controller),
        ),
        // Custom scrub surface. Tap to seek, drag to scrub in real
        // time (video preview follows the finger). 16px vertical
        // padding gives a comfortable tap target, but the bar itself
        // is only 3px tall so it reads as a thin accent line.
        _ScrubBar(
          progress: progress,
          color: widget.scrubBarColor ?? AppColors.seed,
          onSeekFraction: (frac) {
            final newMs = (durationMs * frac).round();
            controller.seekTo(Duration(milliseconds: newMs));
          },
        ),
      ],
    );
  }
}

class _ScrubBar extends StatelessWidget {
  final double progress;
  final Color color;
  final ValueChanged<double> onSeekFraction;

  const _ScrubBar({
    required this.progress,
    required this.color,
    required this.onSeekFraction,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekFromDx(double dx) {
          final frac = (dx / width).clamp(0.0, 1.0);
          onSeekFraction(frac);
        }

        // Hit area is 16px tall but the visible accent line sits flush at
        // the TOP so it touches the video's bottom edge. Remaining 13px
        // below are invisible hit-test padding to make the tiny bar
        // comfortable to tap on mobile.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekFromDx(d.localPosition.dx),
          onHorizontalDragStart: (d) => seekFromDx(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekFromDx(d.localPosition.dx),
          child: SizedBox(
            height: 16,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 3,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.black.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
