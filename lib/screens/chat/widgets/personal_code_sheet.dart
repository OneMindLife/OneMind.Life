import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../models/personal_code.dart';
import '../../../providers/providers.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/qr_code_share.dart';

class PersonalCodeSheet extends ConsumerStatefulWidget {
  final int chatId;
  final String chatName;

  const PersonalCodeSheet({
    super.key,
    required this.chatId,
    required this.chatName,
  });

  @override
  ConsumerState<PersonalCodeSheet> createState() => _PersonalCodeSheetState();
}

class _PersonalCodeSheetState extends ConsumerState<PersonalCodeSheet> {
  List<PersonalCode>? _codes;
  bool _isLoading = true;
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    try {
      final service = ref.read(personalCodeServiceProvider);
      final codes = await service.listCodes(widget.chatId);
      if (mounted) {
        setState(() {
          _codes = codes;
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

  Future<void> _generateCode() async {
    setState(() => _isGenerating = true);

    try {
      final service = ref.read(personalCodeServiceProvider);
      final code = await service.generateCode(widget.chatId);

      if (mounted) {
        setState(() {
          _codes = [code, ...?_codes];
          _isGenerating = false;
        });

        // Show QR dialog for the new code
        QrCodeShareDialog.show(
          context,
          chatName: widget.chatName,
          inviteCode: code.code,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        context.showErrorSnackBar(e.toString());
      }
    }
  }

  Future<void> _revokeCode(PersonalCode code) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.revokeCode),
        content: Text(l10n.revokeCodeConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.revokeCode),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final service = ref.read(personalCodeServiceProvider);
      await service.revokeCode(code.id);

      if (mounted) {
        setState(() {
          _codes = _codes?.map((c) {
            if (c.id == code.id) {
              return PersonalCode(
                id: c.id,
                code: c.code,
                label: c.label,
                usedBy: c.usedBy,
                usedAt: c.usedAt,
                revokedAt: DateTime.now(),
                createdAt: c.createdAt,
              );
            }
            return c;
          }).toList();
        });
        context.showSuccessSnackBar(l10n.codeRevoked);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(e.toString());
      }
    }
  }

  void _showCodeQr(PersonalCode code) {
    QrCodeShareDialog.show(
      context,
      chatName: widget.chatName,
      inviteCode: code.code,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title + Generate button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.vpn_key, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.personalCodes,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _isGenerating ? null : _generateCode,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: Text(l10n.generateNewCode),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Code list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _codes == null || _codes!.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  l10n.noCodesYet,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _codes!.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                              itemBuilder: (context, index) {
                                final code = _codes![index];
                                return _PersonalCodeTile(
                                  code: code,
                                  onShowQr: () => _showCodeQr(code),
                                  onRevoke: code.isActive
                                      ? () => _revokeCode(code)
                                      : null,
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }
}

class _PersonalCodeTile extends StatelessWidget {
  final PersonalCode code;
  final VoidCallback onShowQr;
  final VoidCallback? onRevoke;

  const _PersonalCodeTile({
    required this.code,
    required this.onShowQr,
    this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = code.status == PersonalCodeStatus.active;
    final isUsed = code.status == PersonalCodeStatus.used;

    final statusLabel = switch (code.status) {
      PersonalCodeStatus.active => l10n.codeStatusActive,
      PersonalCodeStatus.used => l10n.codeStatusUsed,
      PersonalCodeStatus.revoked => l10n.codeStatusRevoked,
    };

    final statusColor = switch (code.status) {
      PersonalCodeStatus.active => Colors.green,
      PersonalCodeStatus.used => colorScheme.onSurfaceVariant,
      PersonalCodeStatus.revoked => colorScheme.error,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isActive
              ? Icons.vpn_key
              : isUsed
                  ? Icons.check_circle_outline
                  : Icons.block,
          color: isActive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        code.code,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
              color: isActive ? null : colorScheme.onSurfaceVariant,
            ),
      ),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (code.label != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                code.label!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: isActive
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.qr_code, size: 20),
                  tooltip: 'QR Code',
                  onPressed: onShowQr,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: l10n.linkCopied,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code.code));
                    if (context.mounted) {
                      context.showSuccessSnackBar(l10n.codeCopied);
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.block, size: 20, color: colorScheme.error),
                  tooltip: l10n.revokeCode,
                  onPressed: onRevoke,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            )
          : null,
    );
  }
}
