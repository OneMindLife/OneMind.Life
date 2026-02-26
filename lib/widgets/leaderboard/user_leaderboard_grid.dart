import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/generated/app_localizations.dart';
import '../error_view.dart';
import '../../models/user_round_rank.dart';
import '../../providers/providers.dart';
import 'leaderboard_grid_painter.dart';
import 'user_rank_card.dart';

/// Widget displaying users positioned on a 0-100 vertical grid based on their round rank.
///
/// Shows all users who participated in the round.
/// Users are positioned vertically based on their rank score:
/// - Higher rank = higher position on screen
/// - 100 = top, 0 = bottom
class UserLeaderboardGrid extends ConsumerStatefulWidget {
  final int roundId;
  final int myParticipantId;

  const UserLeaderboardGrid({
    super.key,
    required this.roundId,
    required this.myParticipantId,
  });

  @override
  ConsumerState<UserLeaderboardGrid> createState() => _UserLeaderboardGridState();
}

class _UserLeaderboardGridState extends ConsumerState<UserLeaderboardGrid> {
  List<UserRoundRank>? _userRanks;
  bool _isLoading = true;
  String? _error;

  // Zoom and scroll state (matching propositions tab)
  double _zoomLevel = 1.0;
  final ScrollController _scrollController = ScrollController();
  double _currentScrollOffset = 0.0;
  double? _lastAvailableHeight;

  // Layout constants (matching propositions tab)
  static const double _topBuffer = 75.0;
  static const double _bottomBuffer = 75.0;
  static const double _cardMaxWidth = 280.0;

  @override
  void initState() {
    super.initState();
    _loadUserRanks();
    _scrollController.addListener(() {
      setState(() {
        _currentScrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRanks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final propositionService = ref.read(propositionServiceProvider);
      final ranks = await propositionService.getUserRoundRanks(
        roundId: widget.roundId,
        myParticipantId: widget.myParticipantId,
      );
      if (mounted) {
        setState(() {
          _userRanks = ranks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _zoomIn() {
    final oldZoom = _zoomLevel;
    final newZoom = (oldZoom * 1.25).clamp(1.0, 10.0);

    if (oldZoom == newZoom) return;

    setState(() {
      _zoomLevel = newZoom;
    });

    // Adjust scroll to keep view centered
    if (_lastAvailableHeight != null && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final targetScroll = (_currentScrollOffset * newZoom / oldZoom).clamp(0.0, maxScroll);
        _scrollController.jumpTo(targetScroll);
      });
    }
  }

  void _zoomOut() {
    final oldZoom = _zoomLevel;
    final newZoom = (oldZoom / 1.25).clamp(1.0, 10.0);

    if (oldZoom == newZoom) return;

    setState(() {
      _zoomLevel = newZoom;
    });

    // Adjust scroll to keep view centered
    if (_lastAvailableHeight != null && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final targetScroll = (_currentScrollOffset * newZoom / oldZoom).clamp(0.0, maxScroll);
        _scrollController.jumpTo(targetScroll);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorView(
        isCompact: true,
        message: l10n.error(_error!),
        onRetry: _loadUserRanks,
      );
    }

    if (_userRanks == null || _userRanks!.isEmpty) {
      return Center(
        child: Text(
          l10n.noLeaderboardData,
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    // Find the highest-ranked user (leaderboard winner)
    final topRankedParticipantId = _userRanks!.isNotEmpty
        ? _userRanks!.reduce((a, b) => a.rank > b.rank ? a : b).participantId
        : null;

    return Row(
      children: [
        // Main grid area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _buildGridArea(constraints, topRankedParticipantId, theme);
            },
          ),
        ),
        // Zoom controls (matching propositions tab style)
        Container(
          padding: const EdgeInsets.all(4),
          child: _buildZoomControls(theme),
        ),
      ],
    );
  }

  Widget _buildGridArea(BoxConstraints constraints, int? topRankedParticipantId, ThemeData theme) {
    final availableHeight = constraints.maxHeight;
    final gridHeight = availableHeight * _zoomLevel;

    _lastAvailableHeight = availableHeight;

    return SingleChildScrollView(
      controller: _scrollController,
      child: SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            // Border decoration (matching propositions tab)
            Positioned(
              top: _topBuffer,
              left: 0,
              right: 0,
              bottom: _topBuffer,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            // Content layer
            Positioned.fill(
              child: Stack(
                children: [
                  // Grid background with labels
                  Positioned(
                    top: _topBuffer,
                    left: 0,
                    right: 0,
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, gridHeight - (_topBuffer + _bottomBuffer)),
                      painter: LeaderboardGridPainter(
                        labelColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        labelStyle: theme.textTheme.bodySmall ?? const TextStyle(),
                        viewportHeight: constraints.maxHeight,
                        scrollOffset: _currentScrollOffset - _topBuffer,
                      ),
                    ),
                  ),

                  // User rank cards
                  Positioned.fill(
                    child: Row(
                      children: [
                        const SizedBox(width: 30), // Space for labels
                        Expanded(
                          child: Stack(
                            children: _buildUserCards(gridHeight, topRankedParticipantId),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildUserCards(double gridHeight, int? topRankedParticipantId) {
    final stackHeight = gridHeight - (_topBuffer + _bottomBuffer);

    return _userRanks!.map((userRank) {
      // Calculate y position based on rank (0-100)
      // Higher rank = higher position (lower y value)
      final yPercent = 1 - (userRank.rank / 100);
      final yPosition = (yPercent * stackHeight) + _topBuffer;

      // Determine if this is the current user or the top-ranked user
      final isCurrentUser = userRank.participantId == widget.myParticipantId;
      final isWinner = userRank.participantId == topRankedParticipantId;

      return Positioned(
        top: yPosition,
        left: 0,
        right: 0,
        child: FractionalTranslation(
          translation: const Offset(0, -0.5), // Center card vertically on position
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
              child: UserRankCard(
                userRank: userRank,
                isCurrentUser: isCurrentUser,
                isWinner: isWinner,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildZoomControls(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom in button
            AspectRatio(
              aspectRatio: 1.0,
              child: GestureDetector(
                onTap: _zoomIn,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.zoom_in,
                    size: 25,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Zoom out button
            AspectRatio(
              aspectRatio: 1.0,
              child: GestureDetector(
                onTap: _zoomOut,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.zoom_out,
                    size: 25,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
