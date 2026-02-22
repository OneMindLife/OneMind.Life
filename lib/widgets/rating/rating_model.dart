import 'package:flutter/material.dart';

/// Represents the different phases of the ranking process
enum RatingPhase {
  binary, // Initial comparison of two messages
  positioning, // Placing new messages on the grid
  completed // All messages have been ranked
}

/// Represents a proposition that can be ranked
class RatingProposition {
  final String id;
  final String content;
  final double position; // 0-100 scale (DISPLAY position)
  final double truePosition; // TRUE position (unrounded, for compression)
  final bool isActive; // Currently being positioned
  final int placementOrder; // Order in which card was placed

  const RatingProposition({
    required this.id,
    required this.content,
    required this.position,
    double? truePosition,
    this.isActive = false,
    this.placementOrder = 0,
  }) : truePosition = truePosition ?? position;

  RatingProposition copyWith({
    String? id,
    String? content,
    double? position,
    double? truePosition,
    bool? isActive,
    int? placementOrder,
  }) {
    return RatingProposition(
      id: id ?? this.id,
      content: content ?? this.content,
      position: position ?? this.position,
      truePosition: truePosition ?? this.truePosition,
      isActive: isActive ?? this.isActive,
      placementOrder: placementOrder ?? this.placementOrder,
    );
  }
}

/// Tracks cards at the same position (stack)
class PositionStack {
  final double position;
  final String defaultCardId;
  final List<String> allCardIds;
  final String? preservedDefaultId;

  PositionStack({
    required this.position,
    required this.defaultCardId,
    required this.allCardIds,
    this.preservedDefaultId,
  });

  int get cardCount => allCardIds.length;
  bool get hasMultipleCards => allCardIds.length > 1;
}

/// State model for the grid ranking widget
class RatingModel extends ChangeNotifier {
  final List<Map<String, dynamic>> _inputPropositions;

  /// Callback when a placement is confirmed and more propositions may be needed
  final void Function()? onPlacementConfirmed;

  /// Callback when undo removes a proposition (returns the removed proposition ID)
  final void Function(String removedId)? onUndo;

  /// Callback to save rankings after each placement
  /// Parameters: rankings map (id -> position), whether all positions changed (compression)
  final void Function(Map<String, double> rankings, bool allPositionsChanged)? onSaveRankings;

  /// Whether we're in lazy loading mode (propositions added incrementally)
  final bool lazyLoadingMode;

  RatingPhase _phase = RatingPhase.binary;
  List<RatingProposition> _rankedPropositions = [];
  int _currentPropositionIndex = 0;
  double _virtualPosition = 50.0;
  double _previousVirtualPosition = 50.0;
  bool _justUndid = false;
  bool _wasDragging = false;

  /// When true, we're expanding from compressed state back toward normal
  /// Active card stays at boundary until expansion completes
  bool _isExpanding = false;

  /// Compressed positions saved when entering expansion mode
  Map<String, double> _compressedPositions = {};

  /// How much "expansion progress" we've made (0 = fully compressed, 1 = fully expanded)
  double _expansionProgress = 0.0;

  /// Which boundary we're expanding from (true = top/100, false = bottom/0)
  bool _expandingFromTop = false;

  /// Whether more propositions are expected (for lazy loading)
  bool _morePropositionsExpected = false;

  /// Whether we need to fetch more propositions after widget is ready (for resume)
  bool _needsFetchAfterInit = false;

  final Map<String, double> _basePositions = {};
  final Map<String, double> _originalPositions = {};
  final Map<double, PositionStack> _positionStacks = {};
  int _placementCounter = 0;

  /// ID of the most recently placed proposition (for optimized saves)
  String? _lastPlacedId;

  /// Positions of inactive cards at the START of the current placement
  /// Used to detect compression/expansion that happened during drag
  final Map<String, double> _positionsAtPlacementStart = {};

  /// Whether resuming from saved rankings (propositions include 'position' field)
  final bool isResuming;

  RatingModel(
    List<Map<String, dynamic>> propositions, {
    this.onPlacementConfirmed,
    this.onUndo,
    this.onSaveRankings,
    this.lazyLoadingMode = false,
    this.isResuming = false,
  }) : _inputPropositions = List.from(propositions) {
    _morePropositionsExpected = lazyLoadingMode;
    if (isResuming) {
      _initializeFromSavedRankings();
    } else {
      _initializeBinaryComparison();
    }
  }

  /// Factory constructor for read-only results display.
  /// Creates a model in completed state with propositions positioned by their final ratings.
  ///
  /// [propositions] should contain maps with 'id', 'content', and 'finalRating' keys.
  /// The finalRating (0-100) is mapped directly to position (0-100).
  factory RatingModel.fromResults(List<Map<String, dynamic>> propositions) {
    final model = RatingModel._forResults();

    for (final prop in propositions) {
      final id = prop['id'].toString();
      final content = prop['content'] as String;
      // Use finalRating as the position (both are 0-100 scale)
      final rating = (prop['finalRating'] as num?)?.toDouble() ?? 50.0;

      model._rankedPropositions.add(RatingProposition(
        id: id,
        content: content,
        position: rating,
        truePosition: rating,
        isActive: false,
        placementOrder: model._placementCounter++,
      ));
    }

    model._currentPropositionIndex = propositions.length;
    model._phase = RatingPhase.completed;
    model._detectStacks();

    return model;
  }

  /// Private constructor for fromResults factory
  RatingModel._forResults()
      : _inputPropositions = [],
        onPlacementConfirmed = null,
        onUndo = null,
        onSaveRankings = null,
        lazyLoadingMode = false,
        isResuming = false;

  RatingPhase get phase => _phase;
  List<RatingProposition> get rankedPropositions =>
      List.unmodifiable(_rankedPropositions);
  int get currentPropositionIndex => _currentPropositionIndex;
  double get virtualPosition => _virtualPosition;
  bool get isComplete => _currentPropositionIndex >= _inputPropositions.length && !_morePropositionsExpected;
  bool get morePropositionsExpected => _morePropositionsExpected;
  bool get needsFetchAfterInit => _needsFetchAfterInit;

  /// Clear the needs fetch flag (call after handling it)
  void clearNeedsFetchAfterInit() {
    _needsFetchAfterInit = false;
  }
  int get totalPropositions => _inputPropositions.length;
  Map<double, PositionStack> get positionStacks =>
      Map.unmodifiable(_positionStacks);

  /// Get current rankings as a map (id -> position)
  Map<String, double> get currentRankings {
    final rankings = <String, double>{};
    for (final prop in _rankedPropositions) {
      if (!prop.isActive) {
        rankings[prop.id] = prop.position;
      }
    }
    return rankings;
  }

  /// Save current rankings via callback
  /// [allPositionsChanged] indicates if compression/expansion happened
  /// When false, only sends the newly placed proposition to optimize network traffic
  void _saveCurrentRankings({required bool allPositionsChanged}) {
    if (onSaveRankings == null) return;

    Map<String, double> rankings;
    if (allPositionsChanged || _lastPlacedId == null) {
      // Send all rankings when compression happened or initial placement
      rankings = currentRankings;
    } else {
      // Only send the newly placed proposition
      final lastPlaced = _rankedPropositions.firstWhere(
        (p) => p.id == _lastPlacedId,
        orElse: () => _rankedPropositions.first,
      );
      rankings = {_lastPlacedId!: lastPlaced.position};
    }

    onSaveRankings!(rankings, allPositionsChanged);
  }

  /// Add a proposition dynamically (for lazy loading)
  /// Call this after onPlacementConfirmed callback
  void addProposition(Map<String, dynamic> proposition) {
    _inputPropositions.add(proposition);
    // Only start positioning if we're in positioning phase and there's no active card
    if (_phase == RatingPhase.positioning) {
      final hasActive = _rankedPropositions.any((p) => p.isActive);
      if (!hasActive) {
        _addNextProposition();
      }
    }
  }

  /// Signal that no more propositions are available
  /// This will trigger completion if all current propositions are placed
  void setNoMorePropositions() {
    _morePropositionsExpected = false;
    // If we're in positioning phase with no active card, complete
    if (_phase == RatingPhase.positioning) {
      final hasActive = _rankedPropositions.any((p) => p.isActive);
      if (!hasActive) {
        _phase = RatingPhase.completed;
        notifyListeners();
      }
    }
  }

  void _initializeBinaryComparison() {
    if (_inputPropositions.length >= 2) {
      _rankedPropositions = [
        RatingProposition(
          id: _inputPropositions[0]['id'].toString(),
          content: _inputPropositions[0]['content'],
          position: 100.0,
          isActive: false,
        ),
        RatingProposition(
          id: _inputPropositions[1]['id'].toString(),
          content: _inputPropositions[1]['content'],
          position: 0.0,
          isActive: false,
        ),
      ];

      _originalPositions[_inputPropositions[0]['id'].toString()] = 100.0;
      _originalPositions[_inputPropositions[1]['id'].toString()] = 0.0;
      _currentPropositionIndex = 2;
      _detectStacks();
    }
    notifyListeners();
  }

  /// Initialize from saved rankings (resuming a previous session)
  void _initializeFromSavedRankings() {
    // Create ranked propositions from saved data
    _rankedPropositions = [];
    _placementCounter = 0;

    for (final prop in _inputPropositions) {
      final id = prop['id'].toString();
      final content = prop['content'] as String;
      final position = (prop['position'] as num).toDouble();

      _rankedPropositions.add(RatingProposition(
        id: id,
        content: content,
        position: position,
        truePosition: position,
        isActive: false,
        placementOrder: _placementCounter++,
      ));

      _originalPositions[id] = position;
      _basePositions[id] = position;
    }

    _currentPropositionIndex = _inputPropositions.length;
    _detectStacks();

    // Skip binary phase - go directly to positioning (or completed)
    if (_morePropositionsExpected) {
      _phase = RatingPhase.positioning;
      // Set flag to fetch more after widget is ready (can't call callback during construction)
      _needsFetchAfterInit = true;
    } else {
      _phase = RatingPhase.completed;
    }

    notifyListeners();
  }

  void swapBinaryPositions() {
    if (_phase != RatingPhase.binary || _rankedPropositions.length != 2) {
      return;
    }

    final temp = _rankedPropositions[0].position;
    _rankedPropositions[0] =
        _rankedPropositions[0].copyWith(position: _rankedPropositions[1].position);
    _rankedPropositions[1] = _rankedPropositions[1].copyWith(position: temp);

    _originalPositions[_rankedPropositions[0].id] = _rankedPropositions[0].position;
    _originalPositions[_rankedPropositions[1].id] = _rankedPropositions[1].position;

    notifyListeners();
  }

  void confirmBinaryChoice() {
    if (_phase != RatingPhase.binary) return;

    _phase = RatingPhase.positioning;

    // Save the initial binary rankings (both positions are new)
    _saveCurrentRankings(allPositionsChanged: true);

    // In lazy loading mode, request more propositions via callback
    if (lazyLoadingMode && _morePropositionsExpected) {
      onPlacementConfirmed?.call();
      notifyListeners();
    } else {
      _addNextProposition();
    }
  }

  void _addNextProposition() {
    if (_currentPropositionIndex >= _inputPropositions.length) {
      // In lazy loading mode, we wait for more propositions
      // Only complete if we're not expecting more
      if (!_morePropositionsExpected) {
        _phase = RatingPhase.completed;
      }
      notifyListeners();
      return;
    }

    // Capture positions at the START of this placement (before any dragging)
    // This is used to detect compression/expansion that happens during drag
    _positionsAtPlacementStart.clear();
    for (var prop in _rankedPropositions) {
      if (!prop.isActive) {
        _positionsAtPlacementStart[prop.id] = prop.position;
      }
    }

    final nextProposition = _inputPropositions[_currentPropositionIndex];
    final newCardId = nextProposition['id'].toString();
    _rankedPropositions.add(
      RatingProposition(
        id: newCardId,
        content: nextProposition['content'],
        position: 50.0,
        isActive: true,
      ),
    );
    _virtualPosition = 50.0;
    _currentPropositionIndex++;

    if (!_originalPositions.containsKey(newCardId)) {
      _originalPositions[newCardId] = 50.0;
    }

    _basePositions.clear();
    for (var prop in _rankedPropositions) {
      if (!prop.isActive) {
        final isCleanPosition = prop.position >= 0 &&
            prop.position <= 100 &&
            (prop.position == prop.position.roundToDouble() ||
                (prop.position * 10).round() == (prop.position * 10));

        if (isCleanPosition) {
          _basePositions[prop.id] = prop.position;
        } else {
          _basePositions[prop.id] = _originalPositions[prop.id] ?? prop.position;
        }
      }
    }

    _detectStacks();
    notifyListeners();
  }

  void moveActiveProposition(double delta) {
    if (_phase != RatingPhase.positioning) return;

    final activeIndex = _rankedPropositions.indexWhere((p) => p.isActive);
    if (activeIndex == -1) return;

    debugPrint('[RATING] move: vPos=$_virtualPosition prevVPos=$_previousVirtualPosition delta=$delta expanding=$_isExpanding');
    for (final p in _rankedPropositions) {
      debugPrint('[RATING]   ${p.id}: pos=${p.position.toStringAsFixed(1)} active=${p.isActive}');
    }

    if (_justUndid) {
      _virtualPosition = _previousVirtualPosition;
      _justUndid = false;
    }

    // Handle decompression mode - the boundary card (originally at 100 or 0)
    // pins immediately to the boundary. Other compressed cards decompress
    // smoothly toward original positions. Active card moves freely.
    if (_isExpanding) {
      final isMovingAwayFromBoundary =
          (_expandingFromTop && delta < 0) ||
          (!_expandingFromTop && delta > 0);

      if (isMovingAwayFromBoundary) {
        final boundary = _expandingFromTop ? 100.0 : 0.0;

        // Move active card normally (NOT pinned at boundary)
        _virtualPosition += delta;
        final activePos = _virtualPosition.clamp(0.0, 100.0);
        _rankedPropositions[activeIndex] = _rankedPropositions[activeIndex].copyWith(
          position: activePos,
        );

        // Decompression progress = how far active has moved from boundary.
        // Use /30 instead of /100 so decompression completes in ~30 units
        // of movement, making it feel responsive.
        final distanceFromBoundary = (activePos - boundary).abs();
        _expansionProgress = (distanceFromBoundary / 30.0).clamp(0.0, 1.0);

        // Boundary card (originally at 100 or 0) pins to the boundary
        // immediately. Other compressed cards interpolate smoothly.
        for (int i = 0; i < _rankedPropositions.length; i++) {
          if (i != activeIndex) {
            final propId = _rankedPropositions[i].id;
            final original = _originalPositions[propId];

            // Pin boundary card to boundary — it stays at 100 (or 0) until
            // the active card overtakes it via normal movement.
            if (original == boundary) {
              _rankedPropositions[i] = _rankedPropositions[i].copyWith(
                position: boundary,
                truePosition: boundary,
              );
              _compressedPositions.remove(propId);
              continue;
            }

            final compressed = _compressedPositions[propId];
            if (compressed != null && original != null) {
              final newPos = compressed + (original - compressed) * _expansionProgress;
              _rankedPropositions[i] = _rankedPropositions[i].copyWith(
                position: newPos.clamp(0.0, 100.0),
                truePosition: newPos.clamp(0.0, 100.0),
              );
            }
          }
        }

        // Update base positions to current state
        _basePositions.clear();
        for (var prop in _rankedPropositions) {
          if (!prop.isActive) {
            _basePositions[prop.id] = prop.position;
          }
        }

        // If fully decompressed, exit decompression mode
        if (_expansionProgress >= 1.0) {
          _isExpanding = false;
          _compressedPositions.clear();
          for (var prop in _rankedPropositions) {
            if (!prop.isActive) {
              _originalPositions[prop.id] = prop.position;
            }
          }
        }

        _detectStacks();
        notifyListeners();
        return;
      } else {
        // Moving back toward/past boundary - exit decompression mode
        // Update base positions to current state to avoid visual jump
        _isExpanding = false;
        _compressedPositions.clear();
        _basePositions.clear();
        for (var prop in _rankedPropositions) {
          if (!prop.isActive) {
            _basePositions[prop.id] = prop.position;
          }
        }
      }
    }

    final currentDirection = delta.sign;
    final previousDirection = (_virtualPosition - _previousVirtualPosition).sign;

    if (currentDirection != previousDirection ||
        _previousVirtualPosition == _virtualPosition ||
        _wasDragging) {
      _previousVirtualPosition = _virtualPosition;
      _wasDragging = false;
    }

    _virtualPosition += delta;
    _applyPositionWithCompression(activeIndex);

    _detectStacks();
    notifyListeners();
  }

  /// Handle movement during expansion mode
  /// All cards expand gradually from compressed positions to their final targets.
  void _handleExpansionMove(double amount, int activeIndex) {
    _expansionProgress += amount / 100.0;
    if (_expansionProgress > 1.0) _expansionProgress = 1.0;

    final towardTop = _expandingFromTop;

    // Collect inactive card indices that have compressed positions
    final inactiveIndices = <int>[];
    for (int i = 0; i < _rankedPropositions.length; i++) {
      if (i != activeIndex &&
          _compressedPositions.containsKey(_rankedPropositions[i].id)) {
        inactiveIndices.add(i);
      }
    }
    if (inactiveIndices.isEmpty) return;

    // Find the compressed range
    double compMin = double.infinity, compMax = double.negativeInfinity;
    for (final idx in inactiveIndices) {
      final c = _compressedPositions[_rankedPropositions[idx].id]!;
      if (c < compMin) { compMin = c; }
      if (c > compMax) { compMax = c; }
    }
    final compRange = compMax - compMin;

    if (compRange <= 0) {
      // All cards at same compressed position: snap all to the boundary together
      final boundary = towardTop ? 100.0 : 0.0;
      for (final idx in inactiveIndices) {
        _rankedPropositions[idx] =
            _rankedPropositions[idx].copyWith(position: boundary);
      }
    } else {
      // All cards gradually interpolate from compressed to final positions
      for (final idx in inactiveIndices) {
        final compressed = _compressedPositions[_rankedPropositions[idx].id]!;
        // Final target: linear map from [compMin, compMax] to [0, 100]
        final double finalPos =
            ((compressed - compMin) / compRange) * 100.0;
        final newPos = compressed + (finalPos - compressed) * _expansionProgress;
        _rankedPropositions[idx] =
            _rankedPropositions[idx].copyWith(position: newPos.clamp(0.0, 100.0));
      }
    }

    // Update base positions
    _basePositions.clear();
    for (var prop in _rankedPropositions) {
      if (!prop.isActive) {
        _basePositions[prop.id] = prop.position;
      }
    }

    // If expansion is complete, exit expansion mode
    if (_expansionProgress >= 1.0) {
      _isExpanding = false;
      _compressedPositions.clear();
      _previousVirtualPosition = _virtualPosition;
      // Update original positions to the expanded state
      for (var prop in _rankedPropositions) {
        if (!prop.isActive) {
          _originalPositions[prop.id] = prop.position;
        }
      }
    }
  }

  void setActivePropositionPosition(double position) {
    if (_phase != RatingPhase.positioning) return;

    final activeIndex = _rankedPropositions.indexWhere((p) => p.isActive);
    if (activeIndex == -1) return;

    if (_justUndid) {
      _virtualPosition = _previousVirtualPosition;
      _justUndid = false;
    }

    final delta = position - _virtualPosition;
    final currentDirection = delta.sign;
    final previousDirection = (_virtualPosition - _previousVirtualPosition).sign;

    if (currentDirection != previousDirection ||
        _previousVirtualPosition == _virtualPosition) {
      _previousVirtualPosition = _virtualPosition;
    }

    _virtualPosition = position;
    _wasDragging = true;
    _applyPositionWithCompression(activeIndex);
    _detectStacks();
    notifyListeners();
  }

  /// Normalize virtualPosition to boundary when button is released while past bounds.
  /// All cards stay at their current visual positions (no jump on release).
  /// Enters decompression mode so the next opposite-direction move restores positions.
  void normalizeVirtualPositionOnRelease() {
    if (_phase != RatingPhase.positioning) return;

    final wasAbove100 = _virtualPosition > 100;
    final wasBelow0 = _virtualPosition < 0;

    if (wasAbove100 || wasBelow0) {
      final boundary = wasAbove100 ? 100.0 : 0.0;
      _virtualPosition = boundary;
      _previousVirtualPosition = boundary;

      // Save ALL compressed positions — no visual change on release
      _compressedPositions.clear();
      for (var prop in _rankedPropositions) {
        if (!prop.isActive) {
          _compressedPositions[prop.id] = prop.position;
        }
      }

      _isExpanding = true;
      _expandingFromTop = wasAbove100;
      _expansionProgress = 0.0;

      _basePositions.clear();
      for (var prop in _rankedPropositions) {
        if (!prop.isActive) {
          _basePositions[prop.id] = prop.position;
        }
      }

      notifyListeners();
    }
  }

  void _applyPositionWithCompression(int activeIndex) {
    if (_basePositions.isEmpty) {
      for (var prop in _rankedPropositions) {
        if (!prop.isActive) {
          _basePositions[prop.id] = prop.position;
        }
      }
    }

    bool needsCompressionAt100 = _virtualPosition >= 99.9 &&
        _rankedPropositions.any((p) => !p.isActive && p.position >= 99.9);
    bool needsCompressionAt0 = _virtualPosition <= 0.1 &&
        _rankedPropositions.any((p) => !p.isActive && p.position <= 0.1);

    bool isExactlyAtBoundary = (_virtualPosition == 100.0 || _virtualPosition == 0.0);
    bool shouldCompress = (_virtualPosition > 100 || _virtualPosition < 0) ||
        (needsCompressionAt100 && !isExactlyAtBoundary) ||
        (needsCompressionAt0 && !isExactlyAtBoundary);

    if (shouldCompress) {
      _applyCompressionBeyondBounds(activeIndex);
    } else {
      _rankedPropositions[activeIndex] = _rankedPropositions[activeIndex].copyWith(
        position: _virtualPosition,
      );

      bool wasCompressed =
          _previousVirtualPosition >= 100 || _previousVirtualPosition <= 0;
      bool nowNormal = _virtualPosition > 0 && _virtualPosition < 100;
      bool transitioningFromCompressed = wasCompressed && nowNormal;

      // When active card leaves a boundary, expand inactive cards toward that boundary
      if (transitioningFromCompressed) {
        final leavingTop = _previousVirtualPosition >= 100;
        final leavingBottom = _previousVirtualPosition <= 0;
        final noInactiveAtTop = !_rankedPropositions.any(
            (p) => !p.isActive && p.position >= 99.5);
        final noInactiveAtBottom = !_rankedPropositions.any(
            (p) => !p.isActive && p.position <= 0.5);

        if ((leavingTop && noInactiveAtTop) ||
            (leavingBottom && noInactiveAtBottom)) {
          debugPrint('[RATING] Expanding toward ${leavingTop ? "top" : "bottom"} boundary');
          _expandTowardBoundary(activeIndex, leavingTop);
        }
      }

      // Normal movement - just use base positions for inactive cards
      for (int i = 0; i < _rankedPropositions.length; i++) {
        if (i != activeIndex) {
          String propId = _rankedPropositions[i].id;
          double basePos = _basePositions[propId] ?? _rankedPropositions[i].position;
          _rankedPropositions[i] =
              _rankedPropositions[i].copyWith(position: basePos);
        }
      }
    }
  }

  /// Expand inactive cards toward a vacated boundary.
  /// When active leaves top (100): stretch highest inactive to 100, keep lowest in place.
  /// When active leaves bottom (0): stretch lowest inactive to 0, keep highest in place.
  void _expandTowardBoundary(int activeIndex, bool towardTop) {
    final inactiveProps = <RatingProposition>[];
    for (int i = 0; i < _rankedPropositions.length; i++) {
      if (i != activeIndex) {
        inactiveProps.add(_rankedPropositions[i]);
      }
    }
    if (inactiveProps.length < 2) return;

    inactiveProps.sort((a, b) => a.position.compareTo(b.position));

    final currentMin = inactiveProps.first.position;
    final currentMax = inactiveProps.last.position;
    final currentRange = currentMax - currentMin;
    if (currentRange <= 0) return;

    // Stretch only toward the vacated boundary, keep the other end fixed
    final double targetMin = towardTop ? currentMin : 0.0;
    final double targetMax = towardTop ? 100.0 : currentMax;
    final targetRange = targetMax - targetMin;

    for (int i = 0; i < inactiveProps.length; i++) {
      final relativePosition = (inactiveProps[i].position - currentMin) / currentRange;
      final newPosition = (targetMin + relativePosition * targetRange).clamp(0.0, 100.0);

      final propIndex = _rankedPropositions.indexWhere((p) => p.id == inactiveProps[i].id);
      if (propIndex != -1) {
        _rankedPropositions[propIndex] = _rankedPropositions[propIndex].copyWith(
          position: newPosition,
          truePosition: newPosition,
        );
      }
    }

    _basePositions.clear();
    for (var prop in _rankedPropositions) {
      if (!prop.isActive) {
        _basePositions[prop.id] = prop.position;
      }
    }

    // Also update originalPositions so future compression references the expanded state
    for (var prop in _rankedPropositions) {
      if (!prop.isActive) {
        _originalPositions[prop.id] = prop.position;
      }
    }
  }

  void _expandCompressedPositions(int activeIndex) {
    List<RatingProposition> inactiveProps = [];
    for (int i = 0; i < _rankedPropositions.length; i++) {
      if (i != activeIndex) {
        inactiveProps.add(_rankedPropositions[i]);
      }
    }

    if (inactiveProps.isEmpty) return;

    inactiveProps.sort((a, b) => a.position.compareTo(b.position));

    final currentMin = inactiveProps.first.position;
    final currentMax = inactiveProps.last.position;
    final currentRange = currentMax - currentMin;

    const targetMin = 0.0;
    const targetMax = 100.0;
    const targetRange = targetMax - targetMin;

    if (currentRange > 0) {
      for (int i = 0; i < inactiveProps.length; i++) {
        final oldPosition = inactiveProps[i].position;
        final relativePosition = (oldPosition - currentMin) / currentRange;
        final newPosition = targetMin + (relativePosition * targetRange);

        final propIndex =
            _rankedPropositions.indexWhere((p) => p.id == inactiveProps[i].id);
        if (propIndex != -1) {
          _rankedPropositions[propIndex] = _rankedPropositions[propIndex].copyWith(
            position: newPosition,
            truePosition: newPosition,
          );
        }
      }

      _basePositions.clear();
      for (var prop in _rankedPropositions) {
        if (!prop.isActive) {
          _basePositions[prop.id] = prop.position;
        }
      }
    }
  }

  void _applyCompressionBeyondBounds(int activeIndex) {
    if (_virtualPosition >= 100) {
      double overflow = _virtualPosition - 100;
      double compressionRatio = 100 / (100 + overflow);

      _rankedPropositions[activeIndex] =
          _rankedPropositions[activeIndex].copyWith(position: 100);

      for (int i = 0; i < _rankedPropositions.length; i++) {
        if (i != activeIndex) {
          String propId = _rankedPropositions[i].id;
          double baseTruePos =
              _basePositions[propId] ?? _rankedPropositions[i].truePosition;
          double newTruePos = baseTruePos * compressionRatio;
          newTruePos = newTruePos.clamp(0.0, 100.0);

          _rankedPropositions[i] = _rankedPropositions[i].copyWith(
            position: newTruePos,
            truePosition: newTruePos,
          );
        }
      }
    } else if (_virtualPosition <= 0) {
      double underflow = -_virtualPosition;
      if (underflow == 0) underflow = 0.1;
      double compressionRatio = 100 / (100 + underflow);

      _rankedPropositions[activeIndex] =
          _rankedPropositions[activeIndex].copyWith(position: 0);

      for (int i = 0; i < _rankedPropositions.length; i++) {
        if (i != activeIndex) {
          String propId = _rankedPropositions[i].id;
          double baseTruePos =
              _basePositions[propId] ?? _rankedPropositions[i].truePosition;
          double newTruePos = 100 - (100 - baseTruePos) * compressionRatio;
          newTruePos = newTruePos.clamp(0.0, 100.0);

          _rankedPropositions[i] = _rankedPropositions[i].copyWith(
            position: newTruePos,
            truePosition: newTruePos,
          );
        }
      }
    } else {
      _rankedPropositions[activeIndex] =
          _rankedPropositions[activeIndex].copyWith(position: _virtualPosition);

      for (int i = 0; i < _rankedPropositions.length; i++) {
        if (i != activeIndex) {
          String propId = _rankedPropositions[i].id;
          double basePos = _basePositions[propId] ?? _rankedPropositions[i].position;
          _rankedPropositions[i] =
              _rankedPropositions[i].copyWith(position: basePos);
        }
      }
    }
  }

  void confirmPlacement() {
    if (_phase != RatingPhase.positioning) return;

    final activeIndex = _rankedPropositions.indexWhere((p) => p.isActive);
    if (activeIndex == -1) return;

    // Track the ID of the proposition being placed (for optimized saves)
    _lastPlacedId = _rankedPropositions[activeIndex].id;

    _placementCounter++;
    _rankedPropositions[activeIndex] = _rankedPropositions[activeIndex].copyWith(
      isActive: false,
      placementOrder: _placementCounter,
    );

    _normalizePositions();

    // Check if any existing positions changed from the START of this placement
    // This detects compression/expansion that happened during drag, not just normalization
    bool compressionHappened = false;
    for (final prop in _rankedPropositions) {
      if (!prop.isActive && _positionsAtPlacementStart.containsKey(prop.id)) {
        if ((_positionsAtPlacementStart[prop.id]! - prop.position).abs() > 0.5) {
          compressionHappened = true;
          break;
        }
      }
    }

    _basePositions.clear();
    for (var prop in _rankedPropositions) {
      if (!prop.isActive) {
        _basePositions[prop.id] = prop.position;
      }
    }
    _basePositions[_rankedPropositions[activeIndex].id] =
        _rankedPropositions[activeIndex].position;

    _detectStacks();

    // Save rankings after placement
    _saveCurrentRankings(allPositionsChanged: compressionHappened);

    // In lazy loading mode, notify that we need more propositions
    if (lazyLoadingMode && _morePropositionsExpected) {
      // Call the callback to request more propositions
      // The screen will call addProposition() or setNoMorePropositions()
      onPlacementConfirmed?.call();
      notifyListeners();
    } else {
      _addNextProposition();
    }
  }

  void _normalizePositions() {
    final inactiveProps = _rankedPropositions.where((p) => !p.isActive).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    if (inactiveProps.isEmpty) return;

    for (int i = 0; i < inactiveProps.length; i++) {
      final prop = inactiveProps[i];
      double normalizedDisplayPos = prop.position.round().toDouble();
      normalizedDisplayPos = normalizedDisplayPos.clamp(0.0, 100.0);

      if (i > 0) {
        final prevProp = inactiveProps[i - 1];
        final prevPos = prevProp.position;
        final wereAtDifferentPositions =
            (prop.truePosition - prevProp.truePosition).abs() > 0.01;

        if (normalizedDisplayPos < prevPos && wereAtDifferentPositions) {
          normalizedDisplayPos = prevPos + 1.0;
          normalizedDisplayPos = normalizedDisplayPos.clamp(0.0, 100.0);
        }
      }

      final propIndex = _rankedPropositions.indexWhere((p) => p.id == prop.id);
      if (propIndex != -1) {
        _rankedPropositions[propIndex] =
            _rankedPropositions[propIndex].copyWith(position: normalizedDisplayPos);
      }
    }
  }

  void undoLastPlacement() {
    if (_phase != RatingPhase.positioning) return;
    if (_rankedPropositions.length <= 2) return;

    final activeProp = _rankedPropositions.firstWhere(
      (p) => p.isActive,
      orElse: () => _rankedPropositions.last,
    );

    final wasAtTop = activeProp.position >= 99.9;
    final wasAtBottom = activeProp.position <= 0.1;

    // Store the ID before removing
    final removedId = activeProp.id;

    _rankedPropositions.removeWhere((p) => p.isActive);

    // In lazy loading mode, remove from input so it can be re-fetched via onUndo.
    // In non-lazy mode, keep it in _inputPropositions so _addNextProposition
    // can re-add it when the binary choice is re-confirmed.
    if (lazyLoadingMode) {
      _inputPropositions.removeWhere((p) => p['id'].toString() == removedId);
    }

    // Notify that this proposition was undone (for lazy loading to re-fetch)
    onUndo?.call(removedId);

    if (wasAtTop || wasAtBottom) {
      _uncompressAfterUndo();
    }

    _basePositions.clear();
    for (var prop in _rankedPropositions) {
      _basePositions[prop.id] = prop.position;
    }

    if (_rankedPropositions.length == 2) {
      _phase = RatingPhase.binary;
      _currentPropositionIndex = 2;
    } else {
      var sortedByPlacementOrder = List<RatingProposition>.from(_rankedPropositions)
        ..sort((a, b) => b.placementOrder.compareTo(a.placementOrder));

      final lastPlaced = sortedByPlacementOrder.first;
      final propIndex = _rankedPropositions.indexWhere((p) => p.id == lastPlaced.id);

      _rankedPropositions[propIndex] =
          _rankedPropositions[propIndex].copyWith(isActive: true);
      _virtualPosition = _rankedPropositions[propIndex].position;
      _previousVirtualPosition = _virtualPosition;
      _justUndid = false;
      _currentPropositionIndex--;

      debugPrint('[RATING] Undo: reactivated ${lastPlaced.id} at pos=${_virtualPosition}');
      for (final p in _rankedPropositions) {
        debugPrint('[RATING]   ${p.id}: pos=${p.position.toStringAsFixed(1)} active=${p.isActive}');
      }
    }

    _detectStacks();
    notifyListeners();
  }

  void _uncompressAfterUndo() {
    if (_rankedPropositions.isEmpty) return;

    var sortedByPosition = List<RatingProposition>.from(_rankedPropositions)
      ..sort((a, b) => b.position.compareTo(a.position));

    final highestProp = sortedByPosition.first;
    final lowestProp = sortedByPosition.last;

    if (highestProp.position < 99.0 || lowestProp.position > 1.0) {
      final currentMin = lowestProp.position;
      final currentMax = highestProp.position;
      final currentRange = currentMax - currentMin;

      if (currentRange > 0) {
        const targetMin = 0.0;
        const targetMax = 100.0;
        const targetRange = targetMax - targetMin;

        for (int i = 0; i < sortedByPosition.length; i++) {
          final oldPosition = sortedByPosition[i].position;
          final relativePosition = (oldPosition - currentMin) / currentRange;
          final newPosition = targetMin + (relativePosition * targetRange);

          sortedByPosition[i] =
              sortedByPosition[i].copyWith(position: newPosition);
        }

        _rankedPropositions = sortedByPosition;
      } else {
        // currentRange is 0 - all cards are at the same position!
        _spreadStackedCards(sortedByPosition);
        _rankedPropositions = sortedByPosition;
      }

      // After expansion, check if any cards ended up at the same position
      // and spread them to avoid stacking at boundaries
      _spreadDuplicatePositions();
    }
  }

  /// Spread cards that were all at the same position
  void _spreadStackedCards(List<RatingProposition> props) {
    final count = props.length;
    if (count == 1) {
      // Single card goes to middle
      props[0] = props[0].copyWith(position: 50.0);
    } else if (count == 2) {
      // Two cards: one at 100, one at 0
      props[0] = props[0].copyWith(position: 100.0);
      props[1] = props[1].copyWith(position: 0.0);
    } else {
      // Multiple cards: spread evenly from 100 to 0
      for (int i = 0; i < count; i++) {
        final newPosition = 100.0 - (100.0 * i / (count - 1));
        props[i] = props[i].copyWith(position: newPosition);
      }
    }
  }

  /// After expansion, spread any cards that ended up at the same position
  void _spreadDuplicatePositions() {
    // Group cards by position (with tolerance)
    const tolerance = 0.5;
    final positionGroups = <double, List<int>>{};

    for (int i = 0; i < _rankedPropositions.length; i++) {
      final pos = _rankedPropositions[i].position;
      double? matchingPos;
      for (var existingPos in positionGroups.keys) {
        if ((pos - existingPos).abs() < tolerance) {
          matchingPos = existingPos;
          break;
        }
      }
      if (matchingPos != null) {
        positionGroups[matchingPos]!.add(i);
      } else {
        positionGroups[pos] = [i];
      }
    }

    // Spread any groups with multiple cards
    for (var entry in positionGroups.entries) {
      if (entry.value.length > 1) {
        final pos = entry.key;
        final indices = entry.value;

        // Determine spread direction and amount
        final spreadAmount = 5.0; // Spread by 5 units
        final startOffset = -spreadAmount * (indices.length - 1) / 2;

        for (int j = 0; j < indices.length; j++) {
          final idx = indices[j];
          var newPos = pos + startOffset + (spreadAmount * j);
          newPos = newPos.clamp(0.0, 100.0);

          _rankedPropositions[idx] = _rankedPropositions[idx].copyWith(position: newPos);
        }
      }
    }
  }

  Map<String, double> getFinalRankings() {
    final rankings = <String, double>{};
    for (final prop in _rankedPropositions) {
      rankings[prop.id] = prop.position;
    }
    return rankings;
  }

  void _detectStacks() {
    final oldStacks = Map<double, PositionStack>.from(_positionStacks);
    _positionStacks.clear();

    final isCompressing = _virtualPosition > 100 || _virtualPosition < 0;
    final tolerance = isCompressing ? 0.5 : 0.1;

    final positionGroups = <double, List<RatingProposition>>{};

    for (var prop in _rankedPropositions) {
      double? matchingPosition;
      for (var existingPos in positionGroups.keys) {
        final diff = (prop.position - existingPos).abs();
        if (diff < tolerance) {
          matchingPosition = existingPos;
          break;
        }
      }

      if (matchingPosition != null) {
        positionGroups[matchingPosition]!.add(prop);
      } else {
        positionGroups[prop.position] = [prop];
      }
    }

    for (var entry in positionGroups.entries) {
      if (entry.value.length > 1) {
        PositionStack? oldStack;
        for (var oldEntry in oldStacks.entries) {
          final diff = (entry.key - oldEntry.key).abs();
          if (diff < tolerance) {
            oldStack = oldEntry.value;
            break;
          }
        }

        final allCardIds = entry.value.map((p) => p.id).toList();
        String defaultCardId;
        final hasActiveProp = entry.value.any((p) => p.isActive);
        String? preservedDefaultId;

        if (hasActiveProp) {
          final activeProp = entry.value.firstWhere((p) => p.isActive);
          defaultCardId = activeProp.id;

          if (oldStack != null && oldStack.defaultCardId != activeProp.id) {
            preservedDefaultId = oldStack.defaultCardId;
          } else if (oldStack?.preservedDefaultId != null) {
            preservedDefaultId = oldStack!.preservedDefaultId;
          }
        } else if (oldStack != null &&
            oldStack.preservedDefaultId != null &&
            allCardIds.contains(oldStack.preservedDefaultId!)) {
          defaultCardId = oldStack.preservedDefaultId!;
          preservedDefaultId = null;
        } else if (oldStack != null && allCardIds.contains(oldStack.defaultCardId)) {
          defaultCardId = oldStack.defaultCardId;
        } else {
          final sortedByPlacement = List<RatingProposition>.from(entry.value)
            ..sort((a, b) => b.placementOrder.compareTo(a.placementOrder));
          defaultCardId = sortedByPlacement.first.id;
        }

        _positionStacks[entry.key] = PositionStack(
          position: entry.key,
          defaultCardId: defaultCardId,
          allCardIds: allCardIds,
          preservedDefaultId: preservedDefaultId,
        );
      }
    }
  }

  PositionStack? getStackAtPosition(double position) {
    const tolerance = 0.1;
    for (var entry in _positionStacks.entries) {
      if ((position - entry.key).abs() < tolerance) {
        return entry.value;
      }
    }
    return null;
  }

  void cycleStackCard(double position, String currentCardId) {
    final tolerance = (_virtualPosition > 100 || _virtualPosition < 0) ? 0.5 : 0.1;

    PositionStack? stack;
    double? stackPosition;

    for (var entry in _positionStacks.entries) {
      final diff = (position - entry.key).abs();
      if (diff < tolerance) {
        stack = entry.value;
        stackPosition = entry.key;
        break;
      }
    }

    if (stack == null) {
      _detectStacks();
      for (var entry in _positionStacks.entries) {
        if ((position - entry.key).abs() < tolerance) {
          stack = entry.value;
          stackPosition = entry.key;
          break;
        }
      }
      if (stack == null) return;
    }

    if (!stack.hasMultipleCards) return;

    final cardsAtPosition = stack.allCardIds;
    final currentIndex = cardsAtPosition.indexOf(currentCardId);
    if (currentIndex == -1) return;

    final nextIndex = (currentIndex + 1) % cardsAtPosition.length;
    final nextCardId = cardsAtPosition[nextIndex];

    final preservedId = _positionStacks[stackPosition!]!.preservedDefaultId;

    _positionStacks[stackPosition] = PositionStack(
      position: stackPosition,
      defaultCardId: nextCardId,
      allCardIds: stack.allCardIds,
      preservedDefaultId: preservedId,
    );

    notifyListeners();
  }

  void cyclePreviousStackCard(double position, String currentCardId) {
    final tolerance = (_virtualPosition > 100 || _virtualPosition < 0) ? 0.5 : 0.1;

    PositionStack? stack;
    double? stackPosition;

    for (var entry in _positionStacks.entries) {
      if ((position - entry.key).abs() < tolerance) {
        stack = entry.value;
        stackPosition = entry.key;
        break;
      }
    }

    if (stack == null || !stack.hasMultipleCards) return;

    final cardsAtPosition = stack.allCardIds;
    final currentIndex = cardsAtPosition.indexOf(currentCardId);
    if (currentIndex == -1) return;

    final prevIndex =
        (currentIndex - 1 + cardsAtPosition.length) % cardsAtPosition.length;
    final prevCardId = cardsAtPosition[prevIndex];

    final preservedId = _positionStacks[stackPosition!]!.preservedDefaultId;

    _positionStacks[stackPosition] = PositionStack(
      position: stackPosition,
      defaultCardId: prevCardId,
      allCardIds: stack.allCardIds,
      preservedDefaultId: preservedId,
    );

    notifyListeners();
  }

  bool get areControlsDisabled => false;
}
