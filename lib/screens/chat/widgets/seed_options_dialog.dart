import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../providers/providers.dart';

/// The host's one-time prompt on first arrival in a fresh group quick chat
/// (no cycle yet): how should the ideas come in?
///
/// Replaces the old /create fork screen ("Where do the options come from?").
/// **Leads with the group-proposes path** — OneMind's actual value — as the
/// prominent one-tap default; the poll path (host types fixed options) is
/// tucked behind a deliberate "I already have the options" tap so the dialog
/// doesn't steer people toward a commodity poll.
///   * Default / "Get ideas from the group" / dismiss (X, barrier, back) →
///     pop with null; the caller starts the proposing phase and the group
///     supplies the ideas.
///   * Reveal the editor → seed (>=2 options, typed or AI-generated) → pop
///     with the list; the caller seeds the round and the chat goes straight
///     to voting.
///
/// Outcome of [SeedOptionsDialog]: either the host seeded a fixed option list,
/// or they dismissed the dialog. [dismissMethod] records *how* a dismissal
/// happened so the caller can instrument it:
///   * `x`              — tapped the close (X) button
///   * `group_button`   — tapped the primary "Get ideas from the group"
///   * `barrier_or_back`— tapped outside the dialog or pressed system back
class SeedDialogResult {
  const SeedDialogResult.seeded(List<String> this.options)
      : dismissMethod = null;
  const SeedDialogResult.dismissed(this.dismissMethod) : options = null;

  /// Non-null (>= 2 entries) when the host seeded a fixed list; null on dismiss.
  final List<String>? options;

  /// Non-null on dismissal — one of `x` / `group_button` / `barrier_or_back`.
  final String? dismissMethod;

  bool get seeded => options != null;
}

/// English-only by design (matches the quick-create flow).
class SeedOptionsDialog extends ConsumerStatefulWidget {
  const SeedOptionsDialog({super.key, required this.question});

  /// The chat's deciding question — context for AI option generation.
  final String question;

  /// Shows the dialog and resolves to a [SeedDialogResult]: either seeded
  /// options (>= 2), or a dismissal tagged with *how* it was dismissed (so the
  /// caller can log the method — we couldn't see, e.g., a fast "X without
  /// reading" vs. a deliberate "Get ideas from the group" tap). A barrier tap
  /// or system back returns null from showDialog → mapped to `barrierOrBack`.
  static Future<SeedDialogResult> show(
    BuildContext context, {
    required String question,
  }) async {
    final result = await showDialog<SeedDialogResult>(
      context: context,
      builder: (_) => SeedOptionsDialog(question: question),
    );
    return result ?? const SeedDialogResult.dismissed('barrier_or_back');
  }

  @override
  ConsumerState<SeedOptionsDialog> createState() => _SeedOptionsDialogState();
}

class _SeedOptionsDialogState extends ConsumerState<SeedOptionsDialog> {
  /// Option rows. Starts with 3 (2 = the minimum to vote on, +1 invitation
  /// to think); the host adds more on demand.
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  /// One focus node per option row. On focus we scroll the row into view —
  /// when the soft keyboard opens, the dialog shrinks and a lower row (e.g. the
  /// 5th) ends up hidden behind the keyboard; without this the user has to type
  /// blindly to trigger an auto-scroll. We reveal it the moment it's tapped.
  final List<FocusNode> _focusNodes = [];

  bool _generating = false;

  /// The options editor (the poll path) is collapsed by default so the
  /// dialog leads with — and makes one-tap easy — the group-proposes path,
  /// which is OneMind's actual value. The host reveals the editor only if
  /// they deliberately already have a fixed list to vote on.
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _options.length; i++) {
      _focusNodes.add(_makeFocusNode());
    }
  }

  /// A focus node that, when it gains focus, scrolls its field into view once
  /// the keyboard has finished animating in (so the field isn't left hidden
  /// behind the keyboard inside the shrunk dialog).
  FocusNode _makeFocusNode() {
    final node = FocusNode();
    node.addListener(() {
      if (!node.hasFocus) return;
      // Wait out the keyboard slide-in + the dialog's resize, then reveal.
      Future.delayed(const Duration(milliseconds: 300), () {
        final ctx = node.context;
        if (!mounted || ctx == null || !ctx.mounted) return;
        // Guarded above (state mounted + ctx mounted); safe post-delay.
        // ignore: use_build_context_synchronously
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5, // center the field in the remaining visible area
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    });
    return node;
  }

  @override
  void dispose() {
    for (final c in _options) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  List<String> get _filled => _options
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  bool get _canSeed => _filled.length >= 2;

  void _addRow() => setState(() {
        _options.add(TextEditingController());
        _focusNodes.add(_makeFocusNode());
      });

  /// Bulk AI fill: fills empty rows (adding rows as needed) with suggestions
  /// for [SeedOptionsDialog.question]. Never overwrites a typed row; dedupes
  /// against what's on screen. Quietly no-ops into a snackbar on LLM failure.
  Future<void> _generateWithAi() async {
    if (_generating) return;
    ref
        .read(analyticsServiceProvider)
        .logQuickCreateOptionsAi(source: 'seed_dialog');
    setState(() => _generating = true);
    try {
      final batch = await ref
          .read(chatServiceProvider)
          .generateOptions(question: widget.question, count: 5);
      if (!mounted) return;
      final seen = {for (final s in _filled) s.toLowerCase()};
      var added = false;
      for (final raw in batch) {
        final s = raw.trim();
        if (s.isEmpty || seen.contains(s.toLowerCase())) continue;
        seen.add(s.toLowerCase());
        final emptyIdx = _options.indexWhere((c) => c.text.trim().isEmpty);
        if (emptyIdx >= 0) {
          _options[emptyIdx].text = s;
        } else {
          _options.add(TextEditingController(text: s));
        }
        added = true;
      }
      if (!added) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not suggest options right now')),
        );
      }
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not suggest options right now')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('How should the ideas come in?')),
          IconButton(
            key: const Key('seed-dialog-close'),
            icon: const Icon(Icons.close),
            tooltip: 'Get ideas from the group',
            onPressed: () => Navigator.of(context)
                .pop(const SeedDialogResult.dismissed('x')),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: _showOptions
              ? _buildOptionsEditor(theme)
              : _buildGroupDefault(theme),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: _showOptions
          ? [
              // Secondary: back out to the recommended group path.
              TextButton(
                key: const Key('seed-back-to-group'),
                onPressed: () => setState(() => _showOptions = false),
                child: const Text('Get ideas instead'),
              ),
              FilledButton(
                key: const Key('seed-dialog-start-voting'),
                onPressed: _canSeed
                    ? () => Navigator.of(context)
                        .pop(SeedDialogResult.seeded(_filled))
                    : null,
                child: const Text('Start voting'),
              ),
            ]
          : [
              // Secondary: the poll path, behind a deliberate tap.
              TextButton(
                key: const Key('seed-show-options'),
                onPressed: () => setState(() => _showOptions = true),
                child: const Text('I already have the options'),
              ),
              // PRIMARY default: let the group propose — OneMind's real value.
              FilledButton.icon(
                key: const Key('seed-dialog-group'),
                onPressed: () => Navigator.of(context)
                    .pop(const SeedDialogResult.dismissed('group_button')),
                icon: const Icon(Icons.groups, size: 18),
                label: const Text('Get ideas from the group'),
              ),
            ],
    );
  }

  /// The recommended default: everyone proposes, then the group ranks.
  Widget _buildGroupDefault(ThemeData theme) {
    return Text(
      'Everyone adds an idea, then the group ranks them.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }

  /// The poll path: host types the fixed choices the group will rank.
  Widget _buildOptionsEditor(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Type the choices to rank — voting starts now.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < _options.length; i++)
          Padding(
            key: ObjectKey(_options[i]),
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              key: Key('seed-option-$i'),
              controller: _options[i],
              focusNode: i < _focusNodes.length ? _focusNodes[i] : null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Option ${i + 1}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              key: const Key('seed-add-row'),
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add option'),
            ),
            const Spacer(),
            TextButton.icon(
              key: const Key('seed-generate-ai'),
              onPressed: _generating ? null : _generateWithAi,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Generate with AI'),
            ),
          ],
        ),
      ],
    );
  }
}
