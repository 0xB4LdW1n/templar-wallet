import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'cards.dart';
import 'hex_text.dart';

// The flow (design.md, "The moments"): what a transaction spends on the left,
// where it goes and what it costs on the right, joined by curves through one
// node. Send's review draws it, and a fee bump draws it twice — before and
// after.
//
// Colour here is data (design.md, "Colour as data"): each box is washed in
// the hue of its role and its curve follows — an input in its chain's hue,
// the recipient in the accent, change in `flowChange`, the fee in `flowFee`.
// The role is also a word on the box, so the diagram reads without colour.
//
// Read as a pair — a fee bump's before and after, side by side — the
// diagram is drawn compact and to scale: a box is as tall as what it holds
// is large, on one scale for both, so an output that shrank is a shorter
// box and one that is gone is a missing one.

/// What a box in the flow is.
enum TxFlowRole {
  /// A coin being spent.
  input,

  /// Coins the engine picks itself and does not list (a Liquid send).
  autoInput,

  /// A payment to someone.
  recipient,

  /// The part that comes back to this wallet.
  change,

  /// The network fee.
  fee,
}

/// One box of the flow.
class TxFlowEntry {
  const TxFlowEntry({
    required this.role,
    required this.title,
    required this.amount,
    this.mono = true,
    this.tag,
    this.note,
    this.sats,
  });

  final TxFlowRole role;

  /// An address or an outpoint ([mono]), or a plain description.
  final String title;

  /// The amount, already formatted.
  final String amount;

  /// [title] is something compared character by character.
  final bool mono;

  /// Overrides the role's word ("In", "To", "Change", "Fee").
  final String? tag;

  /// A quiet remark beside the amount: what changed against the other
  /// diagram of a pair ("+987 sats").
  final String? note;

  /// The amount as a number, for a diagram drawn to scale
  /// ([TxFlowDiagram.scaleSats]). Null draws the box at its smallest.
  final int? sats;
}

/// The flow of one transaction: [inputs] on the left, [outputs] (payments,
/// change, and the fee last) on the right. On a phone the two columns become
/// two full-width groups so every address can be read in full.
class TxFlowDiagram extends StatelessWidget {
  const TxFlowDiagram({
    super.key,
    required this.inputs,
    required this.outputs,
    this.liquid = false,
    this.framed = true,
    this.title,
    this.compact = false,
    this.scaleSats,
    this.minBodyHeight,
  });

  final List<TxFlowEntry> inputs;
  final List<TxFlowEntry> outputs;

  /// The transaction is on Liquid: inputs wear the Liquid hue, not Bitcoin's.
  final bool liquid;

  /// Draw the card around the diagram. False when the host already is one
  /// (a dialog).
  final bool framed;

  /// Names the diagram when two are read together ("Before", "After"). It
  /// leads the head row instead of taking a line of its own.
  final String? title;

  /// One of a pair read side by side: smaller boxes that carry the role, the
  /// amount and what changed, with the address left to the tooltip. Desktop
  /// only — a phone stacks the pair and keeps every address in full.
  final bool compact;

  /// Draw to scale: the amount a box of full height holds. A box is then as
  /// tall as its [TxFlowEntry.sats] is large against this, on a square-root
  /// scale so a fee is still a box and not a line. Give both diagrams of a
  /// pair the same value. Null draws every box one height.
  final int? scaleSats;

  static const double _blockH = 64;
  static const double _gap = AppSpacing.md;
  static const double _node = AppSpacing.sm;

  /// A compact box: its smallest (two lines of text) and its tallest.
  static const double _compactMin = 56;
  static const double _compactMax = 96;
  static const double _compactGap = AppSpacing.sm;

  /// The boxes' area is at least this tall (desktop). Give both diagrams
  /// of a pair the larger of their [bodyHeight]s and they are one height,
  /// so their heads line up and the arrow between them sits at mid-flow.
  final double? minBodyHeight;

  /// The height of [entry]'s box in a diagram drawn this way.
  static double _entryHeight(
    TxFlowEntry entry, {
    required bool compact,
    required int? scaleSats,
  }) {
    if (!compact) return _blockH;
    final sats = entry.sats;
    if (scaleSats == null || scaleSats <= 0 || sats == null || sats <= 0) {
      return _compactMin;
    }
    final share = math.sqrt((sats / scaleSats).clamp(0.0, 1.0));
    return _compactMin + (_compactMax - _compactMin) * share;
  }

  static double _columnHeight(List<double> heights, double gap) =>
      heights.fold<double>(0, (sum, h) => sum + h) +
      gap * math.max(0, heights.length - 1);

  /// How tall the boxes' area of a desktop diagram with these entries is:
  /// its taller column. See [minBodyHeight].
  static double bodyHeight({
    required List<TxFlowEntry> inputs,
    required List<TxFlowEntry> outputs,
    bool compact = false,
    int? scaleSats,
  }) {
    final gap = compact ? _compactGap : _gap;
    double column(List<TxFlowEntry> entries) => _columnHeight([
      for (final e in entries)
        _entryHeight(e, compact: compact, scaleSats: scaleSats),
    ], gap);
    return math.max(
      math.max(column(inputs), column(outputs)),
      compact ? _compactMin : _blockH,
    );
  }

  double _heightOf(TxFlowEntry entry) =>
      _entryHeight(entry, compact: compact, scaleSats: scaleSats);

  /// The hue of [role] in this diagram.
  Color _hue(AppScheme s, TxFlowRole role) => switch (role) {
    TxFlowRole.input || TxFlowRole.autoInput => liquid ? s.liquid : s.bitcoin,
    TxFlowRole.recipient => s.accent,
    TxFlowRole.change => s.flowChange,
    TxFlowRole.fee => s.flowFee,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final eyebrow = AppTypography.eyebrow.copyWith(color: s.inkSecondary);
    final paid = outputs.where((o) => o.role != TxFlowRole.fee).length;
    final hasFee = outputs.any((o) => o.role == TxFlowRole.fee);
    final inLabel = title == null
        ? 'Inputs (${inputs.length})'
        : '$title · inputs (${inputs.length})';
    final outLabel = hasFee ? 'Outputs ($paid) and fee' : 'Outputs ($paid)';

    Widget frame(Widget child, double padding) => framed
        ? Container(
            padding: EdgeInsets.all(padding),
            decoration: cardDecoration(s),
            child: child,
          )
        : child;

    if (AppLayout.isPhone(context)) {
      return frame(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(inLabel, style: eyebrow),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < inputs.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _FlowBlock(
                entry: inputs[i],
                hue: _hue(s, inputs[i].role),
                wide: true,
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(child: Divider(color: s.edge, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: _NodeDot(color: s.edgeStrong),
                  ),
                  Expanded(child: Divider(color: s.edge, height: 1)),
                ],
              ),
            ),
            Text(outLabel, style: eyebrow),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < outputs.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _FlowBlock(
                entry: outputs[i],
                hue: _hue(s, outputs[i].role),
                wide: true,
              ),
            ],
          ],
        ),
        AppSpacing.cardPaddingSmall,
      );
    }

    // Each column stacks its boxes with a gap; the shorter column is
    // centred against the taller one, and the curves meet at mid-height.
    final gap = compact ? _compactGap : _gap;
    final inHeights = [for (final e in inputs) _heightOf(e)];
    final outHeights = [for (final e in outputs) _heightOf(e)];
    double columnHeight(List<double> hs) => _columnHeight(hs, gap);
    final height = math.max(
      bodyHeight(
        inputs: inputs,
        outputs: outputs,
        compact: compact,
        scaleSats: scaleSats,
      ),
      minBodyHeight ?? 0,
    );

    /// The top of each box of a column whose boxes are [hs] tall.
    List<double> topsOf(List<double> hs) {
      var y = (height - columnHeight(hs)) / 2;
      final tops = <double>[];
      for (final h in hs) {
        tops.add(y);
        y += h + gap;
      }
      return tops;
    }

    final inTops = topsOf(inHeights);
    final outTops = topsOf(outHeights);

    return frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  inLabel,
                  style: eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Text(outLabel, style: eyebrow, maxLines: 1, softWrap: false),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                // Columns share the width with a lane for the curves between.
                final laneW = compact
                    ? math.min(72.0, math.max(40.0, w * 0.14))
                    : math.min(160.0, math.max(72.0, w * 0.18));
                final colW = (w - laneW) / 2;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FlowPainter(
                          inputs: [
                            for (var i = 0; i < inputs.length; i++)
                              (
                                inTops[i] + inHeights[i] / 2,
                                _hue(s, inputs[i].role),
                              ),
                          ],
                          outputs: [
                            for (var i = 0; i < outputs.length; i++)
                              (
                                outTops[i] + outHeights[i] / 2,
                                _hue(s, outputs[i].role),
                              ),
                          ],
                          leftX: colW,
                          rightX: w - colW,
                          centerX: w / 2,
                          centerY: height / 2,
                          alpha: s.isDark ? 0.7 : 0.8,
                        ),
                      ),
                    ),
                    Positioned(
                      left: w / 2 - _node / 2,
                      top: height / 2 - _node / 2,
                      child: _NodeDot(color: s.inkFaint),
                    ),
                    for (var i = 0; i < inputs.length; i++)
                      Positioned(
                        left: 0,
                        top: inTops[i],
                        width: colW,
                        height: inHeights[i],
                        child: _FlowBlock(
                          entry: inputs[i],
                          hue: _hue(s, inputs[i].role),
                          compact: compact,
                        ),
                      ),
                    for (var i = 0; i < outputs.length; i++)
                      Positioned(
                        right: 0,
                        top: outTops[i],
                        width: colW,
                        height: outHeights[i],
                        child: _FlowBlock(
                          entry: outputs[i],
                          hue: _hue(s, outputs[i].role),
                          compact: compact,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      AppSpacing.cardPadding,
    );
  }
}

/// The junction of the flow: a small neutral dot.
class _NodeDot extends StatelessWidget {
  const _NodeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: TxFlowDiagram._node,
    height: TxFlowDiagram._node,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// The role's word on a tint of the role's hue. The text stays ink: a hue
/// light enough to read as text on a dark card is no longer that hue.
class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.label, required this.hue});

  final String label;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hue.withValues(alpha: s.isDark ? 0.26 : 0.16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      child: Text(label, style: AppTypography.eyebrow.copyWith(color: s.ink)),
    );
  }
}

class _FlowBlock extends StatelessWidget {
  const _FlowBlock({
    required this.entry,
    required this.hue,
    this.wide = false,
    this.compact = false,
  });

  final TxFlowEntry entry;
  final Color hue;

  /// Full-width phone block: the address wraps instead of hiding behind a
  /// hover tooltip, and the block takes the height it needs.
  final bool wide;

  /// One of a pair: the role and what changed on the first line, the amount
  /// on the second; the address is in the tooltip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final recipient = entry.role == TxFlowRole.recipient;
    final tag =
        entry.tag ??
        switch (entry.role) {
          TxFlowRole.input || TxFlowRole.autoInput => 'In',
          TxFlowRole.recipient => 'To',
          TxFlowRole.change => 'Change',
          TxFlowRole.fee => 'Fee',
        };
    final note = entry.note;
    final amount = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: entry.amount,
            style: AppTypography.numeric.copyWith(color: s.ink),
          ),
          if (note != null)
            TextSpan(
              text: '  $note',
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: wide ? TextAlign.end : TextAlign.start,
    );
    final decoration = BoxDecoration(
      color: s.wash(hue),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      // The recipient is the one emphasised box: its edge is the full hue.
      border: Border.all(
        color: recipient ? hue : s.washEdge(hue),
        width: recipient ? 1.5 : 1,
      ),
    );
    const padding = EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    );

    if (wide) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RoleTag(label: tag, hue: hue),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: amount),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            entry.mono
                ? HexText(entry.title, style: AppTypography.monoSmall)
                : Text(
                    entry.title,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
          ],
        ),
      );
    }

    if (compact) {
      return Tooltip(
        message: entry.title,
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: decoration,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RoleTag(label: tag, hue: hue),
                  if (note != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        note,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: AppTypography.label.copyWith(
                          color: s.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              // The figure is never cut: it shrinks to the box instead.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.amount,
                  maxLines: 1,
                  softWrap: false,
                  style: AppTypography.numeric.copyWith(color: s.ink),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: entry.title,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: padding,
        decoration: decoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RoleTag(label: tag, hue: hue),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: entry.mono
                      ? HexText(
                          entry.title,
                          truncate: true,
                          style: AppTypography.monoSmall,
                        )
                      : Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            amount,
          ],
        ),
      ),
    );
  }
}

/// The flow's curves: each input into the node, the node out to each output,
/// every curve in the hue of the box it touches. No arrowheads — left to
/// right is the direction.
class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.inputs,
    required this.outputs,
    required this.leftX,
    required this.rightX,
    required this.centerX,
    required this.centerY,
    required this.alpha,
  });

  /// (centre y, hue) of each box.
  final List<(double, Color)> inputs;
  final List<(double, Color)> outputs;
  final double leftX;
  final double rightX;
  final double centerX;
  final double centerY;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    for (final (y, hue) in inputs) {
      paint.color = hue.withValues(alpha: alpha);
      canvas.drawPath(
        Path()
          ..moveTo(leftX, y)
          ..cubicTo(
            leftX + (centerX - leftX) * 0.5,
            y,
            centerX - (centerX - leftX) * 0.4,
            centerY,
            centerX,
            centerY,
          ),
        paint,
      );
    }
    for (final (y, hue) in outputs) {
      paint.color = hue.withValues(alpha: alpha);
      canvas.drawPath(
        Path()
          ..moveTo(centerX, centerY)
          ..cubicTo(
            centerX + (rightX - centerX) * 0.4,
            centerY,
            rightX - (rightX - centerX) * 0.5,
            y,
            rightX,
            y,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) =>
      !_same(old.inputs, inputs) ||
      !_same(old.outputs, outputs) ||
      old.leftX != leftX ||
      old.rightX != rightX ||
      old.alpha != alpha;

  static bool _same(List<(double, Color)> a, List<(double, Color)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
