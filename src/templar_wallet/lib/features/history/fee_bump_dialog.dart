import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'models/fee_bump_preview.dart';
import 'models/transaction.dart';

Future<FeeBumpPreview?> showFeeBumpDialog(
  BuildContext context, {
  required WalletBridge bridge,
  required String walletId,
  required Transaction transaction,
  required bool cancel,
}) {
  return showAppDialog<FeeBumpPreview>(
    context,
    barrierDismissible: false,
    builder: (_) => _FeeBumpDialog(
      bridge: bridge,
      walletId: walletId,
      transaction: transaction,
      cancel: cancel,
    ),
  );
}

class _FeeBumpDialog extends StatefulWidget {
  const _FeeBumpDialog({
    required this.bridge,
    required this.walletId,
    required this.transaction,
    required this.cancel,
  });

  final WalletBridge bridge;
  final String walletId;
  final Transaction transaction;
  final bool cancel;

  @override
  State<_FeeBumpDialog> createState() => _FeeBumpDialogState();
}

class _FeeBumpDialogState extends State<_FeeBumpDialog> {
  static const _rates = {'slow': 1.0, 'normal': 3.0, 'fast': 8.0};

  late String _method;
  late String _preset;
  late final TextEditingController _custom;
  FeeBumpPreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _method = widget.cancel
        ? 'cancel'
        : widget.transaction.canRbf
        ? 'rbf'
        : 'cpfp';
    final current = widget.transaction.feeRate ?? 0;
    if (8 > current) {
      _preset = 'fast';
      _custom = TextEditingController(text: '8');
    } else {
      _preset = 'custom';
      _custom = TextEditingController(
        text: math.max(current * 1.25, current + 1).toStringAsFixed(1),
      );
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  double? get _rate {
    final value = _preset == 'custom'
        ? double.tryParse(_custom.text.trim())
        : _rates[_preset];
    if (value == null || !value.isFinite || value < 0.1 || value > 1000) {
      return null;
    }
    return value;
  }

  void _changed() {
    setState(() {
      _preview = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final existing = _preview;
    if (existing != null) {
      Navigator.of(context).pop(existing);
      return;
    }
    final rate = _rate;
    if (rate == null) {
      setState(() => _error = 'Enter a fee rate between 0.1 and 1000 sat/vB.');
      return;
    }
    final known = widget.transaction.feeRate;
    if (known != null && rate <= known) {
      setState(
        () => _error =
            'Choose more than ${known.toStringAsFixed(2)} sat/vB, the current rate.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.bridge.previewFeeBump(
        walletId: widget.walletId,
        txid: widget.transaction.txid,
        action: widget.cancel ? 'cancel' : 'speed_up',
        method: widget.cancel ? 'auto' : _method,
        feeRate: rate,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('wallet-ffi: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final preview = _preview;
    final title = widget.cancel
        ? 'Attempt cancellation'
        : 'Speed up transaction';
    final primary = preview == null
        ? (_busy ? 'Building preview…' : 'Preview fee bump')
        : widget.cancel
        ? 'Review cancellation PSBT'
        : 'Review speed-up PSBT';

    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        title: Row(
          children: [
            Icon(
              widget.cancel ? Icons.cancel_outlined : Icons.bolt_rounded,
              size: 20,
              color: widget.cancel ? s.danger : s.inkSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.cancel
                      ? 'This creates a higher-fee replacement paying your own wallet. It is a race: the original payment can still confirm first.'
                      : 'Raise confirmation priority without changing the payment.',
                  style: AppTypography.bodySmall.copyWith(
                    color: s.inkSecondary,
                  ),
                ),
                if (!widget.cancel &&
                    widget.transaction.canRbf &&
                    widget.transaction.canCpfp) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'METHOD',
                    style: AppTypography.navSection.copyWith(color: s.inkFaint),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'rbf',
                        label: Text('RBF'),
                        icon: Icon(Icons.refresh_rounded),
                      ),
                      ButtonSegment(
                        value: 'cpfp',
                        label: Text('CPFP'),
                        icon: Icon(Icons.account_tree_outlined),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: (v) {
                      _method = v.first;
                      _changed();
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'TARGET FEE RATE',
                  style: AppTypography.navSection.copyWith(color: s.inkFaint),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final option in const [
                      ('slow', 'Slow', '1'),
                      ('normal', 'Normal', '3'),
                      ('fast', 'Fast', '8'),
                      ('custom', 'Custom', ''),
                    ])
                      ChoiceChip(
                        label: Text(
                          option.$1 == 'custom'
                              ? option.$2
                              : '${option.$2} · ${option.$3} sat/vB',
                        ),
                        selected: _preset == option.$1,
                        onSelected: (_) {
                          _preset = option.$1;
                          _changed();
                        },
                      ),
                  ],
                ),
                if (_preset == 'custom') ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _custom,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Custom fee rate',
                      suffixText: 'sat/vB',
                    ),
                    onChanged: (_) => _changed(),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (preview == null) ...[
                  _FeeLine(
                    label: 'Current rate',
                    value: widget.transaction.feeRate == null
                        ? 'Calculated during preview'
                        : '${widget.transaction.feeRate!.toStringAsFixed(2)} sat/vB',
                  ),
                  if (widget.transaction.feeSats != null)
                    _FeeLine(
                      label: 'Current fee',
                      value: '${widget.transaction.feeSats} sats',
                    ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: s.panelInset,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Column(
                      children: [
                        _FeeLine(
                          label: 'Method',
                          value: preview.method.toUpperCase(),
                        ),
                        _FeeLine(
                          label: 'Current',
                          value:
                              '${preview.oldFeeSats} sats · ${preview.oldFeeRate.toStringAsFixed(2)} sat/vB',
                        ),
                        _FeeLine(
                          label: preview.isCpfp ? 'Child' : 'Replacement',
                          value:
                              '${preview.newFeeSats} sats · ${preview.newFeeRate.toStringAsFixed(2)} sat/vB',
                        ),
                        _FeeLine(
                          label: 'Extra cost',
                          value: '${preview.extraFeeSats} sats',
                          valueColor: s.danger,
                        ),
                        _FeeLine(
                          label: preview.isCpfp
                              ? 'Package rate'
                              : 'Effective rate',
                          value:
                              '${preview.effectiveFeeRate.toStringAsFixed(2)} sat/vB',
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: phone
            ? [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      label: primary,
                      icon: widget.cancel
                          ? Icons.cancel_outlined
                          : Icons.bolt_rounded,
                      isLoading: _busy,
                      isFullWidth: true,
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SecondaryButton(
                      label: 'Back',
                      isFullWidth: true,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ]
            : [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.cancel
                              ? Icons.cancel_outlined
                              : Icons.bolt_rounded,
                          size: 16,
                        ),
                  label: Text(primary),
                ),
              ],
      ),
    );
  }
}

class _FeeLine extends StatelessWidget {
  const _FeeLine({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.numericSmall.copyWith(
                color: valueColor ?? s.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
