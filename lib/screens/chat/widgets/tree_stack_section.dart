import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../providers/providers.dart';
import '../../../services/proposition_service.dart';
import '../../../services/remote_log_service.dart';
import '../../../models/models.dart';
import '../../../services/matches/match_pair_selector.dart';
import '../../../widgets/message_card.dart';
import 'matches_rating_panel.dart';

/// The user's walk choices per chat (levelKey → chosen option id). Lives in
/// a provider — NOT widget state — so the built stack survives the chat
/// screen's realtime-driven rebuilds/remounts (losing your walk every time a
/// realtime event refreshed the thread was a live-pilot bug).
final treeChoicesProvider = StateProvider.family<Map<int, int>, int>(
  (ref, chatId) => {},
);

/// Levels the user has explicitly re-opened back into their option list.
/// Sealed levels DEFAULT to their winner (the user lands at the leaf with
/// the whole committed spine pre-walked); tapping a block opens it.
final treeOpenLevelsProvider = StateProvider.family<Set<int>, int>(
  (ref, chatId) => {},
);

String _normForMatch(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Function words carry no similarity signal — without this, typing a normal
/// sentence ("the car is going to the place") "matches" nearly every take on
/// the board via the/is/to/and. Kept in sync with the wedge port
/// (wedge/lib/onemind/treeChat.ts STOPWORDS) so both clients filter the same.
const _stopwords = <String>{
  'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'am',
  'i', 'we', 'you', 'he', 'she', 'it', 'they', 'my', 'our', 'your',
  'to', 'of', 'in', 'on', 'at', 'for', 'with', 'and', 'or', 'but',
  'that', 'this', 'these', 'those', 'as', 'so', 'if', 'do', 'does',
  'not', 'no', 'have', 'has', 'had', 'will', 'would', 'should', 'can',
  'think', 'there', 'here', 'what', 'which', 'who', 'how', 'than',
};

/// Signal-bearing tokens of a normalized string: length ≥ 2 and not a
/// stopword. Shared by [similarProps] and [highlightRanges] so filtering and
/// highlighting agree.
List<String> _signalTokens(String norm) => norm
    .split(' ')
    .where((t) => t.length >= 2 && !_stopwords.contains(t))
    .toList(growable: false);

/// Fuzzy-match [query] against proposition contents (the similar-props
/// search under the proposing composer): whole-phrase containment scores
/// highest, then per-token exact and prefix matches. Returns matches
/// best-first; empty when nothing is similar. Top-level so it's unit-testable
/// without pumping the widget.
List<Map<String, dynamic>> similarProps(
  List<Map<String, dynamic>> props,
  String query,
) {
  final q = _normForMatch(query);
  if (q.isEmpty) return const [];
  final qTokens = _signalTokens(q);
  final scored = <(Map<String, dynamic>, double)>[];
  for (final p in props) {
    final c = _normForMatch(p['content'] as String? ?? '');
    if (c.isEmpty) continue;
    var score = 0.0;
    // Whole-phrase bonus only for queries with real signal — a 1-char
    // fragment is contained in nearly everything.
    if (q.length >= 2 && c.contains(q)) score += 3;
    final cTokens = c.split(' ').toSet();
    for (final t in qTokens) {
      if (cTokens.contains(t)) {
        score += 1;
      } else if (t.length >= 3 &&
          cTokens.any(
              (w) => w.length >= 3 && (w.startsWith(t) || t.startsWith(w)))) {
        score += 0.5;
      }
    }
    if (score > 0) scored.add((p, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList(growable: false);
}

/// Character ranges (start, end-exclusive) of the words in [content] that
/// the similar-props search matched for [query] — same token rules as
/// [similarProps] (exact for 2+ chars, prefix for 3+), so the feed can
/// highlight exactly WHY a take was surfaced. Top-level for unit tests.
List<(int, int)> highlightRanges(String content, String query) {
  final qTokens = _signalTokens(_normForMatch(query));
  if (qTokens.isEmpty) return const [];
  final ranges = <(int, int)>[];
  for (final m in RegExp(r'[a-z0-9]+').allMatches(content.toLowerCase())) {
    final w = m.group(0)!;
    final hit = qTokens.any(
      (t) =>
          w == t ||
          (t.length >= 3 &&
              w.length >= 3 &&
              (w.startsWith(t) || t.startsWith(w))),
    );
    if (hit) ranges.add((m.start, m.end));
  }
  return ranges;
}

/// Live standings for a voting round: [props] re-ranked by the pairwise
/// comparisons submitted so far across ALL raters — a win counts 1, a tie
/// counts ½ for both sides, skips count nothing. Stable: equal scores keep
/// the incoming order (the round's ranked/submission order), so a round with
/// no votes yet just numbers the props as they came. Top-level for unit tests.
List<Map<String, dynamic>> liveStandings(
  List<Map<String, dynamic>> props,
  List<PriorVote> votes,
) {
  final score = <int, double>{};
  for (final v in votes) {
    if (v.isSkip) continue;
    if (v.isTie) {
      score[v.winnerId] = (score[v.winnerId] ?? 0) + 0.5;
      score[v.loserId] = (score[v.loserId] ?? 0) + 0.5;
    } else {
      score[v.winnerId] = (score[v.winnerId] ?? 0) + 1;
    }
  }
  final indexed = props.asMap().entries.toList();
  indexed.sort((a, b) {
    final sa = score[a.value['id']] ?? 0.0;
    final sb = score[b.value['id']] ?? 0.0;
    if (sa != sb) return sb.compareTo(sa);
    return a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList(growable: false);
}

/// One committed root position in the chat's history (oldest first):
/// position k's contest was [roundId]; the group chose [winnerId].
class TreePosition {
  final int roundId;
  final int winnerId;
  const TreePosition({required this.roundId, required this.winnerId});
}

/// C15 inline tree stack (docs/ONEMIND_CONCEPT.md C15).
///
/// The chat IS the stack, built option by option:
///   * The user starts at position 1: ALL of round 1's options, shown in
///     final-ranking order (white cards, orange outline; the group's winner
///     carries the primary outline). No expand affordances — CLICKING an
///     option commits it: the options go away and the choice renders as the
///     regular winner card. Tap a committed card to reopen that level.
///   * Positions 1..N are the chat's pre-tree ROOT history (each root round
///     is a position). Choosing a position's WINNER walks forward through
///     history; choosing a SIBLING diverges into that option's subtree
///     (lazy-spawned follow-up subrounds).
///   * After the last committed winner, the walk continues through tree
///     nodes (child cycles): sealed nodes behave like positions; a LIVE node
///     shows its contenders, a Vote button during voting windows, and the
///     composer to add a follow-up. The frontier UI appears ONLY at the leaf.
class TreeStackSection extends ConsumerStatefulWidget {
  final int chatId;
  final int myParticipantId;

  /// The committed root history, oldest first.
  final List<TreePosition> positions;

  /// Transitional: while a ROOT round is still live (it predates the
  /// branching flip), its phase panel renders at the leaf in place of the
  /// empty tip — the root contest IS the frontier's contest until it seals.
  final Widget? liveRootPanel;

  /// Fresh branching chat (no winners yet): the live ROOT round rendered as
  /// position 1's contest — same feed/composer/duel as any node.
  final int? liveRootRoundId;
  final String? liveRootPhase;

  const TreeStackSection({
    super.key,
    required this.chatId,
    required this.myParticipantId,
    required this.positions,
    this.liveRootPanel,
    this.liveRootRoundId,
    this.liveRootPhase,
  });

  @override
  ConsumerState<TreeStackSection> createState() => _TreeStackSectionState();
}

class _TreeStackSectionState extends ConsumerState<TreeStackSection> {

  /// Ranked propositions per ROOT round (positions).
  final Map<int, List<Map<String, dynamic>>> _roundProps = {};

  /// get_node_bootstrap cache per proposition (tree era).
  final Map<int, Map<String, dynamic>> _nodes = {};

  /// ALL raters' pairwise votes per live voting round — powers the standings
  /// list above the duel. Refetched after each of the user's own judgments.
  final Map<int, List<PriorVote>> _roundVotes = {};

  final Set<int> _loadingRounds = {};
  final Set<int> _loadingNodes = {};
  final Set<int> _loadingVotes = {};

  /// Polls the live voting round's standings so OTHER raters' votes move the
  /// board even while this user sits idle (pairwise_comparisons isn't in the
  /// realtime publication — deliberately, per the cascade rules). One timer at
  /// a time, keyed to [_polledRoundId]. Mirrors the wedge's 10s standings poll.
  Timer? _standingsPoll;
  int? _polledRoundId;

  bool _submitting = false;
  final _controller = TextEditingController();

  /// Live feed: refetch the node whose proposing round just received a take.
  RealtimeChannel? _propsChannel;

  /// Participant ids belonging to AI agents in this chat — used to tag
  /// agent-authored propositions everywhere they appear.
  Set<int> _agentIds = {};

  static const _maxDepth = 20;

  @override
  void initState() {
    super.initState();
    if (widget.positions.isNotEmpty) {
      _fetchRound(widget.positions.first.roundId);
    }
    _subscribeToProps();
    _fetchAgentIds();
    // The proposing feed filters live as the user types (similar-props
    // search), so every keystroke re-renders the feed below the composer.
    _controller.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchAgentIds() async {
    try {
      final parts = await ref
          .read(participantServiceProvider)
          .getParticipants(widget.chatId);
      if (mounted) {
        setState(
          () => _agentIds =
              parts.where((p) => p.isAgent).map((p) => p.id).toSet(),
        );
      }
    } catch (_) {
      // Tags degrade gracefully.
    }
  }

  /// Realtime: when anyone submits a proposition in this chat, refresh the
  /// cached node that owns that round so the "what you're up against" feed
  /// updates live. Guarded: in tests Supabase isn't initialized.
  void _subscribeToProps() {
    try {
      _propsChannel = Supabase.instance.client
          .channel('tree_props_${widget.chatId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'propositions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: widget.chatId,
            ),
            callback: (payload) {
              final roundId = payload.newRecord['round_id'] as int?;
              if (roundId == null || !mounted) return;
              if (roundId == widget.liveRootRoundId) {
                _roundProps.remove(roundId);
                _fetchRound(roundId);
                return;
              }
              for (final entry in _nodes.entries) {
                final node = entry.value['node'] as Map<String, dynamic>?;
                final rid =
                    (node?['round'] as Map<String, dynamic>?)?['id'] as int?;
                if (rid == roundId) {
                  _refreshNode(entry.key);
                  break;
                }
              }
            },
          )
          .subscribe();
    } catch (_) {
      // No Supabase in this environment (tests) — feed just won't live-update.
    }
  }

  @override
  void dispose() {
    try {
      _propsChannel?.unsubscribe();
    } catch (_) {}
    _standingsPoll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Ensure a 10s standings poll is running for [roundId] (and no other). Safe
  /// to call from build — re-arms only when the live voting round changes, so
  /// the frequent rebuilds don't churn timers.
  void _ensureStandingsPoll(int roundId) {
    if (_polledRoundId == roundId && _standingsPoll != null) return;
    _standingsPoll?.cancel();
    _polledRoundId = roundId;
    _standingsPoll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchVotes(roundId, force: true),
    );
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _fetchRound(int roundId) async {
    if (_loadingRounds.contains(roundId) || _roundProps.containsKey(roundId)) {
      return;
    }
    _loadingRounds.add(roundId);
    try {
      final svc = ref.read(propositionServiceProvider);
      // Final-ranking order via the get_propositions_with_scores SQL fn
      // (returns proposition_id/content ordered best-first). Falls back to
      // submission order for rounds that never got scores.
      var props = (await svc.getPropositionsWithScores(roundId))
          .map(
            (p) => <String, dynamic>{
              'id': p['proposition_id'] as int,
              'content': p['content'] as String? ?? '',
              'participant_id': p['participant_id'],
            },
          )
          .toList();
      if (props.isEmpty) {
        props = (await svc.getPropositions(roundId))
            .map(
              (p) => <String, dynamic>{'id': p.id, 'content': p.displayContent},
            )
            .toList();
      }
      if (mounted) setState(() => _roundProps[roundId] = props);
    } catch (e) {
      RemoteLog.log('tree_section', 'round fetch failed', {
        'round_id': roundId,
        'error': e.toString(),
      });
    } finally {
      _loadingRounds.remove(roundId);
    }
  }

  Future<void> _fetchNode(int propositionId) async {
    if (_loadingNodes.contains(propositionId) ||
        _nodes.containsKey(propositionId)) {
      return;
    }
    _loadingNodes.add(propositionId);
    try {
      final data = await ref
          .read(chatServiceProvider)
          .getNodeBootstrap(propositionId);
      if (mounted) setState(() => _nodes[propositionId] = data);
    } catch (e) {
      RemoteLog.log('tree_section', 'node fetch failed', {
        'proposition_id': propositionId,
        'error': e.toString(),
      });
    } finally {
      _loadingNodes.remove(propositionId);
    }
  }

  Future<void> _refreshNode(int propositionId) async {
    _nodes.remove(propositionId);
    await _fetchNode(propositionId);
  }

  /// Fetch (or with [force], refetch) every rater's pairwise votes for a live
  /// voting round. On error the standings degrade to the props' incoming
  /// order — cache an empty list so build doesn't refetch in a loop.
  Future<void> _fetchVotes(int roundId, {bool force = false}) async {
    if (_loadingVotes.contains(roundId)) return;
    if (!force && _roundVotes.containsKey(roundId)) return;
    _loadingVotes.add(roundId);
    try {
      final votes = await ref
          .read(propositionServiceProvider)
          .getRoundPairwiseVotes(roundId);
      if (mounted) setState(() => _roundVotes[roundId] = votes);
    } catch (_) {
      if (mounted && !_roundVotes.containsKey(roundId)) {
        setState(() => _roundVotes[roundId] = const []);
      }
    } finally {
      _loadingVotes.remove(roundId);
    }
  }

  bool _isAgentProp(Map<String, dynamic> p) =>
      p['is_agent'] == true || _agentIds.contains(p['participant_id']);

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Committed choice per level (root positions keyed by -roundId; tree
  /// nodes by parent proposition id). Provider-backed: survives remounts.
  Map<int, int> get _choice => ref.read(treeChoicesProvider(widget.chatId));

  /// Levels explicitly opened back into their option list.
  Set<int> get _open => ref.read(treeOpenLevelsProvider(widget.chatId));

  void _commit(int levelKey, int optionId) {
    final n = ref.read(treeChoicesProvider(widget.chatId).notifier);
    n.state = {...n.state, levelKey: optionId};
    final o = ref.read(treeOpenLevelsProvider(widget.chatId).notifier);
    o.state = {...o.state}..remove(levelKey);
  }

  void _reopen(int levelKey) {
    final n = ref.read(treeChoicesProvider(widget.chatId).notifier);
    n.state = {...n.state}..remove(levelKey);
    final o = ref.read(treeOpenLevelsProvider(widget.chatId).notifier);
    o.state = {...o.state, levelKey};
  }

  Future<void> _submitToRound(int roundId) async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(propositionServiceProvider).submitProposition(
            roundId: roundId,
            participantId: widget.myParticipantId,
            content: content,
          );
      _controller.clear();
      _roundProps.remove(roundId);
      await _fetchRound(roundId);
    } on DuplicatePropositionException {
      _snack('That proposition already exists in this round.');
    } catch (_) {
      _snack('Could not submit — try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit(int propositionId) async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final chatService = ref.read(chatServiceProvider);
      var node = _nodes[propositionId]?['node'] as Map<String, dynamic>?;
      if (node == null) {
        await chatService.spawnNodeCycle(propositionId);
        final data = await chatService.getNodeBootstrap(propositionId);
        _nodes[propositionId] = data;
        node = data['node'] as Map<String, dynamic>?;
      }
      final roundId = (node?['round'] as Map<String, dynamic>?)?['id'] as int?;
      if (roundId == null) throw StateError('node round unavailable');
      await ref
          .read(propositionServiceProvider)
          .submitProposition(
            roundId: roundId,
            participantId: widget.myParticipantId,
            content: content,
          );
      _controller.clear();
      await _refreshNode(propositionId);
    } on DuplicatePropositionException {
      _snack('That follow-up already exists here.');
    } catch (e) {
      RemoteLog.log('tree_section', 'submit failed', {
        'proposition_id': propositionId,
        'error': e.toString(),
      });
      _snack(
        e.toString().contains('window_closed')
            ? 'Proposing opens at the next window.'
            : 'Could not submit — try again.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(treeChoicesProvider(widget.chatId));
    ref.watch(treeOpenLevelsProvider(widget.chatId));
    final theme = Theme.of(context);
    final children = <Widget>[];

    // ── Fresh branching chat: the live ROOT round IS position 1 ─────────
    if (widget.positions.isEmpty) {
      final rootId = widget.liveRootRoundId;
      if (rootId == null) return const SizedBox.shrink();
      final props = _roundProps[rootId];
      if (props == null) {
        _fetchRound(rootId);
        children.add(_spinner());
      } else if (widget.liveRootPhase == 'rating') {
        // Standings (current status) above, duel (user action) at the bottom
        // — mirrors the proposing layout.
        children.addAll(
          _votingSection(theme, rootId, props, () async {
            _roundProps.remove(rootId);
            await _fetchRound(rootId);
          }),
        );
      } else {
        // Feed (or similar-props matches while typing) above; composer —
        // the user's action — pinned at the bottom.
        children.addAll(
          _proposingFeed(
            theme,
            props,
            emptyText: 'No propositions yet — be the first.',
          ),
        );
        children.add(_rootComposer(theme, rootId));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }

    int? divergedFrom; // sibling chosen at a root position → tree walk root
    var walkedAllPositions = true;

    // ── Root history: positions 1..N ─────────────────────────────────────
    for (var i = 0; i < widget.positions.length; i++) {
      final pos = widget.positions[i];
      final key = -pos.roundId;
      // Sealed history defaults to the winner — the user lands at the leaf
      // with the spine pre-walked; tapping a block re-opens the level.
      final choice =
          _open.contains(key) ? _choice[key] : (_choice[key] ?? pos.winnerId);

      if (choice == null) {
        final props = _roundProps[pos.roundId];
        if (props == null) {
          _fetchRound(pos.roundId);
          children.add(_spinner());
        } else {
          children.add(_levelHeader(theme, 'PICK ONE'));
          for (var r = 0; r < props.length; r++) {
            final p = props[r];
            final pid = p['id'] as int;
            children.add(
              _optionCard(
                theme,
                content: p['content'] as String? ?? '',
                isAgent: _isAgentProp(p),
                onTap: () => _commit(key, pid),
              ),
            );
          }
        }
        walkedAllPositions = false;
        break;
      }

      final props = _roundProps[pos.roundId];
      if (props == null) {
        // Content cache lost (e.g. remount) — reload instead of rendering an
        // empty committed card.
        _fetchRound(pos.roundId);
        children.add(_spinner());
        walkedAllPositions = false;
        break;
      }
      final chosenProp = props.firstWhere(
        (p) => p['id'] == choice,
        orElse: () => <String, dynamic>{'content': ''},
      );
      children.add(
        _committedCard(
          theme,
          chosenProp['content'] as String? ?? '',
          isAgent: _isAgentProp(chosenProp),
          onTap: () => _reopen(key),
        ),
      );

      if (choice != pos.winnerId) {
        divergedFrom = choice;
        walkedAllPositions = false;
        break;
      }
    }

    // ── Tree era: after the last winner (or down a divergent branch) ─────
    if (walkedAllPositions || divergedFrom != null) {
      final start =
          divergedFrom ??
          (widget.positions.isNotEmpty ? widget.positions.last.winnerId : null);
      if (start != null) {
        // The transitional live-root panel belongs ONLY to the canonical
        // spine's tip — a divergent branch's leaf runs its OWN subround.
        children.addAll(_treeWalk(theme, start, onSpine: divergedFrom == null));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _treeWalk(ThemeData theme, int start, {required bool onSpine}) {
    final children = <Widget>[];
    var current = start;

    for (var depth = 0; depth < _maxDepth; depth++) {
      // Pin the node for this iteration: `current` mutates as the walk
      // continues, and closures must not capture the moving variable.
      final nodeId = current;
      final data = _nodes[nodeId];
      if (data == null) {
        _fetchNode(nodeId);
        children.add(_spinner());
        break;
      }

      final node = data['node'] as Map<String, dynamic>?;
      final windowProposing = data['window_phase'] == 'proposing';

      if (node == null) {
        // The leaf. Only the CANONICAL tip transitionally hosts the live
        // ROOT round's contest — every other leaf is its own subround.
        if (onSpine && widget.liveRootPanel != null) {
          children.add(widget.liveRootPanel!);
        } else {
          children.add(_emptyTip(theme, windowProposing));
          if (windowProposing) children.add(_composer(theme, nodeId));
        }
        break;
      }

      final round = node['round'] as Map<String, dynamic>;
      final sealed = round['completed_at'] != null;
      final winnerId = round['winning_proposition_id'] as int?;
      final props = ((node['propositions'] as List?) ?? const [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      if (winnerId != null) {
        props.sort(
          (a, b) => (a['id'] == winnerId ? 0 : 1).compareTo(
            b['id'] == winnerId ? 0 : 1,
          ),
        );
      }

      final choice = _open.contains(nodeId)
          ? _choice[nodeId]
          : (_choice[nodeId] ?? (sealed ? winnerId : null));

      if (choice != null) {
        final chosenProp = props.firstWhere(
          (p) => p['id'] == choice,
          orElse: () => <String, dynamic>{'content': ''},
        );
        children.add(
          _committedCard(
            theme,
            chosenProp['content'] as String? ?? '',
            isAgent: _isAgentProp(chosenProp),
            onTap: () => _reopen(nodeId),
          ),
        );
        // Leaving the group's winner (or descending from a live node) exits
        // the committed spine.
        if (!sealed || choice != winnerId) onSpine = false;
        current = choice;
        continue;
      }

      // PROPOSING IS BLIND: while a live node collects follow-ups, the takes
      // stay hidden (nobody sees others' submissions before the vote — same
      // rule as everywhere else in the product). Show the count + composer.
      final isBlindProposing = !sealed && round['phase'] == 'proposing';

      // Live voting: standings (current status) render INLINE above the
      // duel (user action) — same layout grammar as the proposing feed.
      if (!sealed && round['phase'] == 'rating') {
        children.addAll(
          _votingSection(
            theme,
            round['id'] as int,
            props,
            () => _refreshNode(nodeId),
          ),
        );
        break;
      }

      if (isBlindProposing) {
        // Live feed of what's already in — so proposers know what they're
        // up against. Read-only cards (not options) above, newest at the
        // bottom next to the composer, filtered to similar takes while the
        // user types; composer pinned at the bottom.
        children.addAll(
          _proposingFeed(
            theme,
            props,
            emptyText: 'No follow-ups here yet — propose the first.',
          ),
        );
        if (windowProposing) children.add(_composer(theme, nodeId));
        break;
      }

      children.add(
        _levelHeader(theme, sealed ? 'PICK ONE' : 'PROPOSITIONS SO FAR'),
      );
      if (props.isEmpty) {
        children.add(_emptyTip(theme, windowProposing));
      } else {
        for (var r = 0; r < props.length; r++) {
          final p = props[r];
          final pid = p['id'] as int;
          children.add(
            _optionCard(
              theme,
              content: p['content'] as String? ?? '',
              isAgent: _isAgentProp(p),
              onTap: () => _commit(nodeId, pid),
            ),
          );
        }
      }
      break;
    }

    return children;
  }

  /// The blind-window proposing feed, shown ABOVE the composer: live-updating,
  /// read-only, newest take at the BOTTOM (adjacent to the composer — chat
  /// idiom). While the user types, the list filters to fuzzy-similar takes
  /// (best match nearest the composer) and the header flips to SIMILAR
  /// PROPOSITIONS — duplicate awareness before they hit send.
  List<Widget> _proposingFeed(
    ThemeData theme,
    List<Map<String, dynamic>> props, {
    required String emptyText,
  }) {
    final query = _controller.text.trim();
    final searching = query.isNotEmpty;
    final items = searching
        ? similarProps(props, query).reversed.toList(growable: false)
        : props;
    final children = <Widget>[
      _levelHeader(
        theme,
        searching ? 'SIMILAR PROPOSITIONS' : 'PROPOSITIONS SO FAR',
      ),
    ];
    if (items.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              searching ? 'Nothing similar yet — yours is new.' : emptyText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    } else {
      for (final p in items) {
        children.add(
          _feedCard(
            theme,
            content: p['content'] as String? ?? '',
            isAgent: _isAgentProp(p),
            highlightQuery: searching ? query : null,
          ),
        );
      }
    }
    return children;
  }

  /// The live voting layout: current standings (every prop with its rank
  /// number, re-sorted as votes land) as the status block, then the duel —
  /// the user's action — at the bottom. Parallel of feed-above-composer.
  List<Widget> _votingSection(
    ThemeData theme,
    int roundId,
    List<Map<String, dynamic>> props,
    Future<void> Function() onDoneRefresh,
  ) {
    final votes = _roundVotes[roundId];
    if (votes == null) _fetchVotes(roundId);
    _ensureStandingsPoll(roundId);
    final ranked = liveStandings(props, votes ?? const []);
    return [
      _levelHeader(theme, 'CURRENT STANDINGS'),
      for (var i = 0; i < ranked.length; i++)
        _standingCard(
          theme,
          rank: i + 1,
          content: ranked[i]['content'] as String? ?? '',
          isAgent: _isAgentProp(ranked[i]),
        ),
      _levelHeader(theme, 'VOTE — TAP THE BETTER ONE'),
      _inlineDuel(roundId, props, onDoneRefresh),
    ];
  }

  /// Inline pairwise voting for a live node — embeds the shared
  /// MatchesRatingPanel (orange accent) with a CSI-aware rateable set.
  Widget _inlineDuel(
    int roundId,
    List<Map<String, dynamic>> props,
    Future<void> Function() onDoneRefresh,
  ) {
    final all = props
        .map(
          (p) => Proposition(
            id: p['id'] as int,
            roundId: roundId,
            participantId: p['participant_id'] as int?,
            content: p['content'] as String? ?? '',
            createdAt:
                DateTime.tryParse(p['created_at'] as String? ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();
    final nonOwn = all
        .where((p) => p.participantId != widget.myParticipantId)
        .toList();
    final rateable = nonOwn.length >= 2 ? nonOwn : all;
    return MatchesRatingPanel(
      key: ValueKey('tree_duel_$roundId'),
      roundId: roundId,
      participantId: widget.myParticipantId,
      rateable: rateable,
      objective: MatchObjective.winnerOnly,
      onSkip: null,
      accentColor: AppColors.consensus,
      // Every persisted judgment refreshes the standings above the duel so
      // the leaderboard moves as the user votes.
      onVote: () => _fetchVotes(roundId, force: true),
      onDone: () async {
        try {
          await ref.read(propositionServiceProvider).markRatingComplete(
                roundId: roundId,
                participantId: widget.myParticipantId,
              );
        } catch (_) {}
        await onDoneRefresh();
      },
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  Widget _spinner() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _levelHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: AppColors.consensus.withValues(alpha: 0.4)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.consensus,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(color: AppColors.consensus.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  /// A committed choice — the regular winner display (AI-authored ones carry
  /// the small AI tag). Tap to reopen the level's options.
  Widget _committedCard(
    ThemeData theme,
    String content, {
    VoidCallback? onTap,
    bool isAgent = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              MessageCard(
                content: content,
                isPrimary: true,
                isConsensus: true,
              ),
              if (isAgent)
                Positioned(
                  top: 2,
                  right: 8,
                  child: Text(
                    'AI',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.consensus,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// An option: looks exactly like a feed item (plain orange border, AI tag
  /// when agent-authored) — but tappable. Click commits.
  Widget _optionCard(
    ThemeData theme, {
    required String content,
    required VoidCallback onTap,
    bool isAgent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(
              color: AppColors.consensus.withValues(alpha: 0.7),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(child: Text(content, style: theme.textTheme.bodyMedium)),
              if (isAgent)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    'AI',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.consensus,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A read-only feed item during blind-window proposing: orange border,
  /// NOT tappable — awareness, not selection. When [highlightQuery] is set
  /// (similar-props search), the matched words render bold + orange.
  Widget _feedCard(
    ThemeData theme, {
    required String content,
    bool isAgent = false,
    String? highlightQuery,
  }) {
    Widget text;
    final ranges = highlightQuery == null
        ? const <(int, int)>[]
        : highlightRanges(content, highlightQuery);
    if (ranges.isEmpty) {
      text = Text(content, style: theme.textTheme.bodyMedium);
    } else {
      final spans = <TextSpan>[];
      var cursor = 0;
      for (final (start, end) in ranges) {
        if (start > cursor) {
          spans.add(TextSpan(text: content.substring(cursor, start)));
        }
        spans.add(
          TextSpan(
            text: content.substring(start, end),
            style: TextStyle(
              color: AppColors.consensus,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        cursor = end;
      }
      if (cursor < content.length) {
        spans.add(TextSpan(text: content.substring(cursor)));
      }
      text = Text.rich(
        TextSpan(style: theme.textTheme.bodyMedium, children: spans),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
            color: AppColors.consensus.withValues(alpha: 0.7),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: text),
            if (isAgent)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'AI',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.consensus,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One row of the live standings: rank number, then the prop — same
  /// read-only orange-border card language as the proposing feed.
  Widget _standingCard(
    ThemeData theme, {
    required int rank,
    required String content,
    bool isAgent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
            color: AppColors.consensus.withValues(alpha: 0.7),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '#$rank',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.consensus,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: Text(content, style: theme.textTheme.bodyMedium)),
            if (isAgent)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'AI',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.consensus,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTip(ThemeData theme, bool windowProposing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          windowProposing
              ? 'No follow-ups here yet — propose the first below.'
              : 'No follow-ups here yet — proposing opens at the next window.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _rootComposer(ThemeData theme, int roundId) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.consensus.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                // The pill Container IS the border — kill every state border
                // (the theme's focusedBorder would otherwise paint a blue
                // outline on focus over the widget-level `border:` fallback).
                decoration: const InputDecoration(
                  hintText: 'Add your own…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitToRound(roundId),
                maxLength: 600,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
              ),
            ),
            IconButton(
              onPressed: _submitting ? null : () => _submitToRound(roundId),
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send, color: AppColors.consensus),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(ThemeData theme, int targetPropositionId) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.consensus.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                // Same as _rootComposer: no state borders, the pill is the
                // border (theme focusedBorder paints blue otherwise).
                decoration: const InputDecoration(
                  hintText: 'Add your own…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(targetPropositionId),
                maxLength: 600,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
              ),
            ),
            IconButton(
              onPressed: _submitting
                  ? null
                  : () => _submit(targetPropositionId),
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send, color: AppColors.consensus),
            ),
          ],
        ),
      ),
    );
  }
}

