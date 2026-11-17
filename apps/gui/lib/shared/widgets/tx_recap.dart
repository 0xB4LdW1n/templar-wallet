import 'package:flutter/material.dart';

import '../../features/send/models/tx_preview.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'hex_text.dart';
import 'hybrid_kit.dart';

/// Everything a transaction does, compactly: each recipient with its amount
/// (and asset, on Liquid), the change, then the fee and the total under a
/// hairline. Printed in a `well`, the box addresses are read in.
///
/// Shown twice in the send flow — once to confirm before signing, once after
/// the broadcast — so both read exactly the same.
class TxRecapPanel extends StatelessWidget {
  const TxRecapPanel({required this.preview, required this.ticker, super.key});

  final TxPreview preview;

  /// Transaction-level ticker, used when an output carries no asset of its own.
  final String ticker;

  /// Below this body width the address and its amount go on separate lines.
  /// A `first12…last8` HexText next to a `0.00010000 BTC` amount needs about
  /// 270 dp; anything narrower would ellipsise the address tail — the part
  /// the user is asked to check. Desktop dialogs give the body 430+ dp, so
  /// the row layout there is untouched.
  static const double _stackBelow = 360;

  bool get isLiquid => preview.chain == 'liquid';

  String amountOf(TxIo o) {
    if (o.amountDisplay != null) return o.amountDisplay!;
    if (isLiquid) return '${o.amountSats} ${o.ticker ?? ticker}';
    return '${(o.amountSats / 1e8).toStringAsFixed(8)} $ticker';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final recipients = preview.outputs.where((o) => !o.isChange).toList();
    final change = preview.outputs.where((o) => o.isChange).toList();

    final amountStyle = AppTypography.numeric.copyWith(color: s.ink);
    final changeStyle = AppTypography.numeric.copyWith(color: s.inkSecondary);
    final eyebrow = AppTypography.eyebrow.copyWith(color: s.inkSecondary);

    return DataWell(
      padding: EdgeInsets.all(phone ? AppSpacing.md : AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = phone || constraints.maxWidth < _stackBelow;

          Widget line(Widget address, Widget amount, {Widget? tag}) {
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tag != null)
                    Row(children: [tag, const Spacer(), amount])
                  else ...[
                    address,
                    const SizedBox(height: AppSpacing.xs),
                    Align(alignment: Alignment.centerRight, child: amount),
                  ],
                  if (tag != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    address,
                  ],
                ],
              );
            }
            return Row(
              children: [
                if (tag != null) ...[tag, const SizedBox(width: AppSpacing.sm)],
                Expanded(child: address),
                const SizedBox(width: AppSpacing.md),
                amount,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                recipients.length == 1
                    ? 'Recipient'
                    : 'Recipients (${recipients.length})',
                style: eyebrow,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < recipients.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                line(
                  HexText(recipients[i].address, truncate: true),
                  Text(amountOf(recipients[i]), style: amountStyle),
                ),
              ],
              for (final c in change) ...[
                const SizedBox(height: AppSpacing.sm),
                line(
                  HexText(c.address, truncate: true),
                  Text(amountOf(c), style: changeStyle),
                  tag: const QuietTag(label: 'Change'),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, thickness: 1, color: s.edge),
              const SizedBox(height: AppSpacing.sm),
              TxKvLine(label: 'Fee', value: preview.feeDisplay),
              const SizedBox(height: AppSpacing.xs),
              TxKvLine(
                label: 'Total',
                value: preview.totalDisplay,
                total: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A key on the left in the secondary ink, its figure right-aligned in the
/// primary ink, used inside the recap.
class TxKvLine extends StatelessWidget {
  const TxKvLine({
    required this.label,
    required this.value,
    this.total = false,
    super.key,
  });

  final String label;
  final String value;

  /// The total: its figure one size up.
  final bool total;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final valueStyle =
        (total ? AppTypography.numericLarge : AppTypography.numeric).copyWith(
          color: s.ink,
        );
    final labelStyle = AppTypography.label.copyWith(color: s.inkSecondary);
    // The value wraps (never overflows) when a Liquid amount with a long
    // ticker does not fit beside its key.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(value, textAlign: TextAlign.right, style: valueStyle),
        ),
      ],
    );
  }
}
