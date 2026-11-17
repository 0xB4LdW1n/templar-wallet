import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/price_service.dart';
import '../../shared/amount_units.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/tx_flow.dart';
import '../psbt/models/psbt_inspection.dart';
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

  /// What the priced replacement (or child) actually spends and pays, as the
  /// engine reads it back from its own PSBT. Null when that read failed: the
  /// fee figures still stand, only the diagrams are left out.
  PsbtInspection? _after;
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
      _after = null;
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
      setState(() => _error = 'Enter a fee rate between 0.1 and 1000 sat/vB');
      return;
    }
    final known = widget.transaction.feeRate;
    if (known != null && rate <= known) {
      setState(
        () => _error =
            'Choose more than ${known.toStringAsFixed(2)} sat/vB, the current rate',
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
      PsbtInspection? after;
      try {
        after = await widget.bridge.inspectPsbt(preview.psbtBase64);
      } catch (_) {
        // The diagrams are a reading aid; the bump itself is already priced.
        after = null;
      }
      if (mounted) {
        setState(() {
          _preview = preview;
          _after = after;
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
    final preview = _preview;
    final tx = widget.transaction;
    final title = widget.cancel
        ? 'Attempt cancellation'
        : 'Speed up transaction';
    // Two steps, one button: first the engine prices the bump, then the
    // priced bump goes on to review and the password gate.
    final primary = preview == null
        ? (_busy ? 'Building preview…' : 'Preview fee bump')
        : widget.cancel
        ? 'Cancel transaction'
        : 'Speed up';

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
      ),
    );

    String rateText(double r) => '${r.toStringAsFixed(2)} sat/vB';

    final after = _after;
    final flows = preview == null || after == null
        ? null
        : _BumpFlows(
            preview: preview,
            after: after,
            original: tx,
            useSats: context.select<AppState, bool>((st) => st.useSats),
          );

    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        title: Text(title),
        // The pair needs room for two diagrams and the arrow between them;
        // the form alone does not.
        maxWidth: 960,
        content: SizedBox(
          width: flows == null
              ? 460
              : math.min(880, MediaQuery.sizeOf(context).width - 96),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.cancel
                      ? 'This creates a higher-fee replacement paying your own wallet. It is a race: the original payment can still confirm first.'
                      : 'Raise confirmation priority without changing the payment.',
                  style: AppTypography.body.copyWith(color: s.inkSecondary),
                ),
                if (!widget.cancel && tx.canRbf && tx.canCpfp) ...[
                  const SizedBox(height: AppSpacing.xl),
                  label('Method'),
                  SegmentedSwitch<String>(
                    options: const [
                      SegOption(value: 'rbf', label: 'RBF'),
                      SegOption(value: 'cpfp', label: 'CPFP'),
                    ],
                    selected: _method,
                    onChanged: (v) {
                      _method = v;
                      _changed();
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                label('Target fee rate'),
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
                      ChoiceTile(
                        label: option.$1 == 'custom'
                            ? option.$2
                            : '${option.$2} · ${option.$3} sat/vB',
                        selected: _preset == option.$1,
                        onSelected: () {
                          _preset = option.$1;
                          _changed();
                        },
                      ),
                  ],
                ),
                if (_preset == 'custom') ...[
                  const SizedBox(height: AppSpacing.lg),
                  label('Custom fee rate'),
                  TextField(
                    controller: _custom,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppTypography.numeric.copyWith(color: s.ink),
                    decoration: const InputDecoration(suffixText: 'sat/vB'),
                    onChanged: (_) => _changed(),
                  ),
                ],
                if (flows != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  flows,
                ],
                const SizedBox(height: AppSpacing.xl),
                DataWell(
                  child: Column(
                    children: preview == null
                        ? [
                            _FeeLine(
                              label: 'Current rate',
                              value: tx.feeRate == null
                                  ? 'Calculated during preview'
                                  : rateText(tx.feeRate!),
                            ),
                            if (tx.feeSats != null)
                              _FeeLine(
                                label: 'Current fee',
                                value: '${_group(tx.feeSats!)} sats',
                              ),
                          ]
                        : [
                            _FeeLine(
                              label: 'Method',
                              value: preview.method.toUpperCase(),
                            ),
                            _FeeLine(
                              label: 'Current fee',
                              value:
                                  '${_group(preview.oldFeeSats)} sats · '
                                  '${rateText(preview.oldFeeRate)}',
                            ),
                            _FeeLine(
                              label: preview.isCpfp ? 'Child fee' : 'New fee',
                              value:
                                  '${_group(preview.newFeeSats)} sats · '
                                  '${rateText(preview.newFeeRate)}',
                            ),
                            _FeeLine(
                              label: 'Extra cost',
                              value: '${_group(preview.extraFeeSats)} sats',
                            ),
                            _FeeLine(
                              label: preview.isCpfp
                                  ? 'Package rate'
                                  : 'Effective rate',
                              value: rateText(preview.effectiveFeeRate),
                            ),
                          ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: AppTypography.body.copyWith(color: s.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Dialog order — the quiet one first, the primary last; a phone
        // sheet stacks them with the primary on top.
        actions: [
          GhostButton(
            label: 'Back',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          PrimaryButton(
            label: primary,
            isLoading: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// One side of the pair: what the transaction spends and what it pays.
typedef _Flow = ({List<TxFlowEntry> inputs, List<TxFlowEntry> outputs});

/// The bump as the flow (design.md, "The moments"): the transaction as it
/// stands on the left, an arrow, and as it will be on the right — two small
/// diagrams in the grammar of Send's review, drawn to one scale, so an
/// output that shrinks is a shorter box and one that goes is a missing one.
///
/// "After" is the engine's own reading of the PSBT it just built. The engine
/// has no call that returns the coins of a transaction already broadcast, so
/// "Before" is worked out, and drawn only where the working is exact:
///
/// - **RBF** of the same shape ([_sameShape]): the same coins and
///   recipients; the fee was the old one (the engine gives it) and the
///   change was larger by the difference.
/// - **Cancel**: the same coins; the payment was the transaction's net
///   outflow less its fee (Activity's own figure), the rest was change.
/// - **CPFP** on a payment of ours: the child spends the payment's change,
///   so the payment is its recipient, that change and its fee — and after,
///   the same payment with less change and both fees.
///
/// Anything else — a replacement that had to add a coin, a child of a
/// payment that came in — gets the one diagram and a line saying what it is.
class _BumpFlows extends StatelessWidget {
  const _BumpFlows({
    required this.preview,
    required this.after,
    required this.original,
    required this.useSats,
  });

  final FeeBumpPreview preview;
  final PsbtInspection after;

  /// The transaction being bumped, as Activity lists it.
  final Transaction original;
  final bool useSats;

  String _coin(int sats) => PriceService.formatUnit(sats, sat: useSats);

  String _rate(double r) => '${r.toStringAsFixed(2)} sat/vB';

  String _delta(int sats) =>
      '${sats >= 0 ? '+' : '−'}${_group(sats.abs())} sats';

  /// What the replacement spends in all, or null when an amount is unknown.
  int? get _spent {
    var sum = 0;
    for (final i in after.inputs) {
      final a = i.amountSats;
      if (a == null) return null;
      sum += a;
    }
    return sum;
  }

  /// The original's net outflow in sats — what Activity prints as its
  /// amount: the payment plus its fee. Null when it is not a plain figure.
  int? get _outflow {
    if (original.direction != TxDirection.outgoing) return null;
    final raw = original.amount.trim().replaceFirst(RegExp(r'^[~+\-−]\s*'), '');
    final space = raw.lastIndexOf(' ');
    final number = (space < 0 ? raw : raw.substring(0, space)).replaceAll(
      ',',
      '',
    );
    final unit = (space < 0 ? original.ticker : raw.substring(space + 1))
        .toUpperCase();
    return switch (unit) {
      'SAT' || 'SATS' => int.tryParse(number),
      'BTC' || 'TBTC' => AmountUnits.satsFromCoin(number),
      _ => null,
    };
  }

  /// Whether an RBF replacement has the original's coins and outputs.
  ///
  /// The engine gives the original's size exactly and the replacement's as
  /// an estimate (its fee over its rate), so the two differ by a few vbytes
  /// even when nothing was added: an estimate prices each signature at its
  /// largest. What cannot hide in that noise is a change of shape — one more
  /// coin is 57 vbytes at the least, a dropped output 31 — so sizes within
  /// a tolerance that stays under those (and grows a little with the number
  /// of coins, capped) mean the same transaction, re-priced.
  bool get _sameShape {
    final tolerance = math.min(40, 12 + 2 * after.inputs.length);
    return (preview.newVsize - preview.oldVsize).abs() <= tolerance;
  }

  /// The replacement's own numbers add up to the fee the engine quoted.
  bool get _reconciles {
    final spent = _spent;
    final fee = after.feeSats;
    if (spent == null || fee == null || fee != preview.newFeeSats) return false;
    final paid = after.outputs.fold<int>(0, (sum, o) => sum + o.amountSats);
    return spent - paid == fee;
  }

  List<TxFlowEntry> _inputs() => [
    for (final i in after.inputs)
      TxFlowEntry(
        role: TxFlowRole.input,
        title: i.outpoint,
        amount: i.amountSats == null ? 'Unknown' : _coin(i.amountSats!),
        sats: i.amountSats,
      ),
  ];

  TxFlowEntry _fee(int sats, double rate, {String? note}) => TxFlowEntry(
    role: TxFlowRole.fee,
    title: _rate(rate),
    amount: '${_group(sats)} sats',
    mono: false,
    note: note,
    sats: sats,
  );

  TxFlowEntry _out(PsbtOutput o, {int? sats, String? note}) => TxFlowEntry(
    role: o.isMine == true ? TxFlowRole.change : TxFlowRole.recipient,
    // A cancellation pays this wallet on purpose: it is not "change".
    tag: o.isMine == true && preview.isCancel ? 'To you' : null,
    title: o.address,
    amount: _coin(sats ?? o.amountSats),
    note: note,
    sats: sats ?? o.amountSats,
  );

  /// The replacement (or child) exactly as the engine reads it back.
  _Flow _afterAsBuilt() => (
    inputs: _inputs(),
    outputs: [
      for (final o in after.outputs) _out(o),
      TxFlowEntry(
        role: TxFlowRole.fee,
        title: _rate(preview.newFeeRate),
        amount: after.feeSats == null
            ? after.feeLabel
            : '${_group(after.feeSats!)} sats',
        mono: false,
        note: preview.isCpfp ? null : _delta(preview.extraFeeSats),
        sats: after.feeSats,
      ),
    ],
  );

  /// Before and after, or null when "before" cannot be worked out exactly.
  ({_Flow before, _Flow after})? _pair() {
    if (!_reconciles) return null;
    final extra = preview.newFeeSats - preview.oldFeeSats;
    final own = after.outputs.where((o) => o.isMine == true).toList();

    if (preview.method == 'rbf') {
      // Same shape: same coins, same outputs. Two boxes differ.
      if (!_sameShape || own.length != 1) return null;
      final change = own.single;
      return (
        before: (
          inputs: _inputs(),
          outputs: [
            for (final o in after.outputs)
              _out(o, sats: identical(o, change) ? o.amountSats + extra : null),
            _fee(preview.oldFeeSats, preview.oldFeeRate),
          ],
        ),
        after: (
          inputs: _inputs(),
          outputs: [
            for (final o in after.outputs)
              _out(o, note: identical(o, change) ? _delta(-extra) : null),
            _fee(preview.newFeeSats, preview.newFeeRate, note: _delta(extra)),
          ],
        ),
      );
    }

    final outflow = _outflow;
    if (outflow == null) return null;
    final paid = outflow - preview.oldFeeSats;
    if (paid <= 0) return null;
    TxFlowEntry recipient() => TxFlowEntry(
      role: TxFlowRole.recipient,
      title: 'The recipient of the payment',
      amount: _coin(paid),
      mono: false,
      sats: paid,
    );

    if (preview.isCancel) {
      // Everything it paid out comes back; only own outputs may remain.
      final spent = _spent!;
      final change = spent - outflow;
      if (change < 0 || own.length != after.outputs.length) return null;
      return (
        before: (
          inputs: _inputs(),
          outputs: [
            recipient(),
            if (change > 0)
              TxFlowEntry(
                role: TxFlowRole.change,
                title: 'Change to this wallet',
                amount: _coin(change),
                mono: false,
                sats: change,
              ),
            _fee(preview.oldFeeSats, preview.oldFeeRate),
          ],
        ),
        after: (
          inputs: _inputs(),
          outputs: [
            for (final o in after.outputs) _out(o),
            _fee(preview.newFeeSats, preview.newFeeRate, note: _delta(extra)),
          ],
        ),
      );
    }

    if (preview.isCpfp) {
      // The child spends the payment's change and returns the rest of it.
      final change = _spent!;
      final returned = own.fold<int>(0, (sum, o) => sum + o.amountSats);
      if (own.length != after.outputs.length || returned <= 0) return null;
      final childFee = preview.newFeeSats;
      TxFlowEntry coins() => TxFlowEntry(
        role: TxFlowRole.input,
        title: 'The coins the payment spends',
        amount: _coin(paid + change + preview.oldFeeSats),
        mono: false,
        sats: paid + change + preview.oldFeeSats,
      );
      TxFlowEntry changeBox(int sats, {String? note}) => TxFlowEntry(
        role: TxFlowRole.change,
        title: note == null
            ? 'Change of the payment, unconfirmed'
            : 'What the child returns to this wallet',
        amount: _coin(sats),
        mono: false,
        note: note,
        sats: sats,
      );
      return (
        before: (
          inputs: [coins()],
          outputs: [
            recipient(),
            changeBox(change),
            _fee(preview.oldFeeSats, preview.oldFeeRate),
          ],
        ),
        after: (
          inputs: [coins()],
          outputs: [
            recipient(),
            changeBox(returned, note: _delta(returned - change)),
            _fee(
              preview.totalFeeSats,
              preview.effectiveFeeRate,
              note: _delta(childFee),
            ),
          ],
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final caption = AppTypography.caption.copyWith(color: s.inkFaint);
    final pair = _pair();

    if (pair != null) {
      // One scale for both sides: the largest box of either.
      var scale = 1;
      for (final e in [
        ...pair.before.inputs,
        ...pair.before.outputs,
        ...pair.after.inputs,
        ...pair.after.outputs,
      ]) {
        final v = e.sats;
        if (v != null && v > scale) scale = v;
      }
      // One height for both, so the heads line up and the arrow sits at
      // the middle of the flows.
      double bodyOf(_Flow flow) => TxFlowDiagram.bodyHeight(
        inputs: flow.inputs,
        outputs: flow.outputs,
        compact: true,
        scaleSats: scale,
      );
      final body = math.max(bodyOf(pair.before), bodyOf(pair.after));
      TxFlowDiagram side(String title, _Flow flow) => TxFlowDiagram(
        framed: false,
        compact: true,
        scaleSats: scale,
        minBodyHeight: phone ? null : body,
        title: title,
        inputs: flow.inputs,
        outputs: flow.outputs,
      );
      final String what;
      if (preview.isCpfp) {
        what =
            'The payment itself does not change: a child spends its change '
            'and pays for both, so the pair confirms at the higher rate. '
            'The payment is worked out from its amount in Activity and its '
            'fee';
      } else if (preview.isCancel) {
        what =
            'The replacement sends the same coins back to this wallet. '
            'Before is worked out from it and from the fee the original paid';
      } else {
        what =
            'Same coins, same payment. Before is worked out from the '
            'replacement and the fee the original paid';
      }
      final arrow = Semantics(
        label: 'becomes',
        child: Icon(
          phone ? Icons.arrow_downward_outlined : Icons.arrow_forward_outlined,
          size: AppSpacing.navIcon,
          color: s.inkSecondary,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phone) ...[
            side('Before', pair.before),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: arrow,
            ),
            side('After', pair.after),
          ] else
            Row(
              children: [
                Expanded(child: side('Before', pair.before)),
                Padding(
                  // Down by half the head row, to the middle of the boxes.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl + AppSpacing.xs,
                    AppSpacing.lg,
                    0,
                  ),
                  child: arrow,
                ),
                Expanded(child: side('After', pair.after)),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Text(what, style: caption),
        ],
      );
    }

    final String title;
    final String what;
    if (preview.isCpfp) {
      title = 'Child transaction';
      what = original.direction == TxDirection.incoming
          ? 'The payment stays as it is. This child spends the coin it sent '
                'you and pays the fee for both'
          : 'The original stays as it is. This child spends its change and '
                'pays the fee for both';
    } else if (preview.isCancel) {
      title = 'Replacement';
      what =
          'It spends the same coins back to this wallet, so the original '
          'can no longer confirm once this does';
    } else {
      title = 'Replacement';
      what =
          'It spends a different set of coins than the original, so only '
          'the replacement is drawn';
    }
    final flow = _afterAsBuilt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TxFlowDiagram(
          framed: false,
          title: title,
          inputs: flow.inputs,
          outputs: flow.outputs,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(what, style: caption),
      ],
    );
  }
}

/// Grouped digits: a fee is money, and `12,480` reads where `12480` does not.
String _group(int n) {
  final digits = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

/// One fee fact: the key in the secondary ink, the figure right-aligned in
/// tabular numerals so the column of figures lines up.
class _FeeLine extends StatelessWidget {
  const _FeeLine({required this.label, required this.value});
  final String label;
  final String value;

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
              style: AppTypography.label.copyWith(color: s.inkSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.numericSmall.copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
  }
}
