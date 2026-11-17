// Who has signed a transaction, and how many signatures are still missing.
//
// Two pictures of the same fact. [SignatureHeader] + [SignerList] are what
// the co-sign panel and the hand-off sheets draw: the state in words, a seal
// per required signature, and one row per key with its seal stamped once the
// engine says that key has signed. [SignerDonut] / [SignerChart] are the
// older ring form, kept for callers that still want a ring; they draw in the
// same neutral material — a key is a hairline arc, a signature is ink.
//
// Pure presentation: counts and slots come in, nothing is computed here that
// the engine did not report. The seal (design.md, "The seal") appears only
// where signatures are counted.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'list_rows.dart' show ListCard, kListPad, kListTile, kListGap;
import 'seal_mark.dart';

/// One signer of a transaction, as the chart draws it.
///
/// [id] is the master fingerprint the transaction names; the rest is what
/// the wallet's labels say about it, when they say anything. A slot with no
/// [name] is shown by its fingerprint.
@immutable
class SignerSlot {
  const SignerSlot({
    required this.id,
    required this.signed,
    this.name,
    this.color,
    this.isHardware = false,
    this.isLocal = false,
  });

  final String id;
  final bool signed;
  final String? name;

  /// The colour the user gave this key, if any. User data: drawn as a small
  /// dot beside the name, never as a fill.
  final Color? color;

  /// This key signs on a USB device — the hand-off sheet offers it.
  final bool isHardware;

  /// This app holds the key.
  final bool isLocal;

  String get label => (name?.trim().isNotEmpty ?? false) ? name!.trim() : id;

  /// Whether the wallet has a name for this key (else [label] is the
  /// fingerprint itself).
  bool get isNamed => name?.trim().isNotEmpty ?? false;
}

// ── The header line and the list ─────────────────────────────────────────────

/// Most seals [SignatureHeader] draws in a row; a larger quorum is stated in
/// words only.
const int maxTallySeals = 7;

/// The transaction's state in words — "Needs 1 more signature" — with a seal
/// per required signature beside it and the count in a caption.
///
/// [signed] and [required] are the engine's numbers (signatures present,
/// signatures the policy needs). With no [required] the tally is not drawn:
/// a row of seals for an unknown quorum would be a number nobody gave us.
class SignatureHeader extends StatelessWidget {
  const SignatureHeader({
    super.key,
    required this.state,
    required this.signed,
    this.required,
    this.caption,
  });

  /// "Needs 1 more signature", "Fully signed, ready to broadcast", …
  final String state;
  final int signed;
  final int? required;

  /// Replaces the default "1 of 2 signatures" line.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final r = required;
    final count =
        caption ??
        (r != null
            ? '$signed of $r signature${r == 1 ? '' : 's'}'
            : '$signed signature${signed == 1 ? '' : 's'} collected');
    final tally = r != null && r > 0 && r <= maxTallySeals
        ? SealTally(signed: signed.clamp(0, r), required: r)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                state,
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
              ),
            ),
            if (tally != null) ...[const SizedBox(width: AppSpacing.md), tally],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          count,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );
  }
}

/// One row per key the transaction names: its seal, its name, its
/// fingerprint, and whether it has signed.
///
/// The seal is stamped only where the slot says the engine saw that key's
/// signature. Rows are keyed by fingerprint, so a signature arriving flips
/// the seal of the row it belongs to — the stamp animates itself.
class SignerList extends StatelessWidget {
  const SignerList({super.key, required this.slots, this.onRename});

  final List<SignerSlot> slots;

  /// Rename a key the wallet knows. Null, or a null answer for a slot, hides
  /// the control on that row.
  final VoidCallback? Function(SignerSlot slot)? onRename;

  @override
  Widget build(BuildContext context) {
    return ListCard(
      children: [
        for (final slot in slots)
          _SignerRow(
            key: ValueKey('signer-${slot.id}'),
            slot: slot,
            onRename: onRename?.call(slot),
          ),
      ],
    );
  }
}

class _SignerRow extends StatelessWidget {
  const _SignerRow({super.key, required this.slot, this.onRename});

  final SignerSlot slot;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final dot = slot.color;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kListPad,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: kListTile,
              child: Center(child: SealMark(stamped: slot.signed)),
            ),
            const SizedBox(width: kListGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (dot != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dot,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(
                          slot.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (slot.isNamed
                                      ? AppTypography.bodyOf(
                                          context,
                                        ).copyWith(fontWeight: FontWeight.w500)
                                      : AppTypography.mono)
                                  .copyWith(color: s.ink),
                        ),
                      ),
                      if (slot.isHardware) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Tooltip(
                          message: 'Signs on a USB device',
                          child: Icon(
                            Icons.usb_outlined,
                            size: AppSpacing.iconSmall,
                            color: s.inkFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (slot.isNamed)
                    Text(
                      slot.id,
                      style: AppTypography.monoSmall.copyWith(
                        color: s.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (slot.isLocal) ...[
              _QuietWord('This wallet'),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              slot.signed ? 'Signed' : 'Not signed',
              style: AppTypography.caption.copyWith(
                color: slot.signed ? s.inkSecondary : s.inkFaint,
              ),
            ),
            if (onRename != null) ...[
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: 'Rename',
                onPressed: onRename,
                constraints: BoxConstraints.tightFor(
                  width: phone ? AppLayout.minTouchTarget : 32,
                  height: phone ? AppLayout.minTouchTarget : 32,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.edit_outlined,
                  size: AppSpacing.iconSmall,
                  color: s.inkSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The quiet tag (design.md, "Tag"): `eyebrow` in the secondary ink on the
/// raised surface, radius 4.
class _QuietWord extends StatelessWidget {
  const _QuietWord(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      child: Text(
        label,
        style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
      ),
    );
  }
}

// ── The ring ─────────────────────────────────────────────────────────────────

/// Ring of [total] signer slots, [signed] of them filled.
///
/// A slot is a hairline arc until its signature arrives, then ink. The
/// centre reads "1 of 3" over "signed". [requiredCount] is what the ring
/// reports to a screen reader; the threshold is not drawn on the ring.
///
/// With [slots] the ring is drawn in their order; [signed] and [total] are
/// then read off the slots.
class SignerDonut extends StatefulWidget {
  const SignerDonut({
    super.key,
    required this.signed,
    required this.total,
    this.requiredCount,
    this.size = 78,
    this.slots,
  });

  /// Signatures already collected. Clamped into `0..total` — a PSBT can carry
  /// a signature from a key the inspection could not attribute to a slot.
  final int signed;

  /// Signer slots the transaction knows about. Zero draws nothing.
  final int total;

  /// Signatures needed to finalize, when the policy says.
  final int? requiredCount;

  final double size;

  /// The signers by name, when the wallet knows them.
  final List<SignerSlot>? slots;

  @override
  State<SignerDonut> createState() => _SignerDonutState();
}

class _SignerDonutState extends State<SignerDonut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  );

  /// Which wedges are being swept in right now — the ones that were not
  /// filled a moment ago. Everything else is drawn already full.
  Set<int> _arriving = const {};
  late List<bool> _filled = _filledNow();

  List<bool> _filledNow() {
    final slots = widget.slots;
    if (slots != null && slots.isNotEmpty) {
      return [for (final s in slots) s.signed];
    }
    final filled = widget.signed.clamp(0, widget.total);
    return [for (var i = 0; i < widget.total; i++) i < filled];
  }

  @override
  void initState() {
    super.initState();
    // First paint: one sweep draws the collected signatures in.
    _arriving = {
      for (var i = 0; i < _filled.length; i++)
        if (_filled[i]) i,
    };
    _sweep.forward(from: 0);
  }

  @override
  void didUpdateWidget(SignerDonut old) {
    super.didUpdateWidget(old);
    final next = _filledNow();
    final arriving = <int>{
      for (var i = 0; i < next.length; i++)
        if (next[i] && !(i < _filled.length && _filled[i])) i,
    };
    _filled = next;
    if (arriving.isNotEmpty) {
      _arriving = arriving;
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final total = _filled.length;
    if (total <= 0) return SizedBox(width: widget.size, height: widget.size);

    final filled = _filled.where((f) => f).length;
    final r = widget.requiredCount;
    final label = r != null
        ? '$filled of $total signers have signed; '
              '$r signature${r == 1 ? '' : 's'} required'
        : '$filled of $total signers have signed';

    // Under reduced motion the ring lands already filled.
    final reduced =
        AppMotion.of(context, AppMotion.emphasized) == Duration.zero;

    return Semantics(
      // One node carrying the whole reading; the centre text is the same
      // numbers in a shorter form.
      container: true,
      excludeSemantics: true,
      label: label,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _sweep,
          builder: (context, _) {
            final t = reduced
                ? 1.0
                : AppMotion.settle.transform(_sweep.value.clamp(0.0, 1.0));
            return CustomPaint(
              painter: _SegmentRingPainter(
                fills: [
                  for (var i = 0; i < total; i++)
                    !_filled[i]
                        ? 0.0
                        : _arriving.contains(i)
                        ? t
                        : 1.0,
                ],
                fillColor: s.ink,
                trackColor: s.edgeStrong,
                strokeFraction: 0.1,
              ),
              child: Padding(
                padding: EdgeInsets.all(widget.size * 0.18),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$filled of $total',
                          style: AppTypography.balanceMedium.copyWith(
                            color: s.ink,
                          ),
                        ),
                        Text(
                          'signed',
                          style: AppTypography.caption.copyWith(
                            color: s.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A ring cut into equal arcs. Each arc is a [trackColor] hairline-weight
/// stroke, filled over by [fillColor] (or its own entry in [fillColors]) as
/// far as its entry in [fills] says. Shared with the cosigner ring, so the
/// two rings are one drawing.
class _SegmentRingPainter extends CustomPainter {
  const _SegmentRingPainter({
    required this.fills,
    required this.fillColor,
    required this.trackColor,
    required this.strokeFraction,
  });

  /// How much of each slot is filled: 0 while pending, fractional while the
  /// arriving signature sweeps in, 1 once it has.
  final List<double> fills;
  final Color fillColor;
  final Color trackColor;

  /// Stroke width as a fraction of the ring's side.
  final double strokeFraction;

  /// Seam between two slots, as a multiple of the stroke width. Round caps
  /// grow each arc by half a stroke at both ends, so a seam narrower than the
  /// stroke closes up and the slots read as one unbroken ring.
  static const _seamStrokes = 1.7;

  /// Ceiling on that seam, as a fraction of one slot — a ring with many
  /// signers must not be all gap.
  static const _maxSeamFraction = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    final total = fills.length;
    if (total == 0) return;
    final stroke = size.shortestSide * strokeFraction;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );
    // 12 o'clock, clockwise — the direction a progress ring is read in.
    const start = -math.pi / 2;
    final slot = (2 * math.pi) / total;
    // A single-signer ring has no seam to draw, so it stays closed.
    final gap = total == 1
        ? 0.0
        : math.min(
            stroke * _seamStrokes / (rect.width / 2),
            slot * _maxSeamFraction,
          );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = total == 1 ? StrokeCap.butt : StrokeCap.round;

    for (var i = 0; i < total; i++) {
      final from = start + i * slot + gap / 2;
      final sweep = slot - gap;
      canvas.drawArc(rect, from, sweep, false, paint..color = trackColor);
      final fill = fills[i].clamp(0.0, 1.0);
      if (fill > 0) {
        canvas.drawArc(
          rect,
          from,
          sweep * fill,
          false,
          paint..color = fillColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SegmentRingPainter old) =>
      !_listEq(old.fills, fills) ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor ||
      old.strokeFraction != strokeFraction;

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The donut, its legend and the quorum line.
///
/// [signed] and [total] are slots on the ring. [collected] is what the
/// inspection actually reports, which can exceed [signed] when a signature
/// could not be attributed to a named signer — it is the number the quorum
/// line prints, never invented from the ring.
///
/// With [slots] the legend names each signer with its seal and Signed / Not
/// signed beside it, in place of the two summary rows.
class SignerChart extends StatelessWidget {
  const SignerChart({
    super.key,
    required this.signed,
    required this.total,
    this.requiredCount,
    this.collected,
    this.caption,
    this.donutSize = 78,
    this.slots,
  });

  final int signed;
  final int total;
  final int? requiredCount;
  final int? collected;

  /// Replaces the default "N signers on this transaction · …" line, for a
  /// ring whose slots are required signatures rather than named signers.
  final String? caption;

  final double donutSize;

  /// The signers by name, when the wallet knows them.
  final List<SignerSlot>? slots;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final slots = this.slots;
    final named = slots != null && slots.isNotEmpty;
    final ringSigned = named ? slots.where((x) => x.signed).length : signed;
    final ringTotal = named ? slots.length : total;
    final present = collected ?? ringSigned;
    final pending = ringTotal - ringSigned;
    final r = requiredCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SignerDonut(
          signed: ringSigned,
          total: ringTotal,
          requiredCount: requiredCount,
          size: donutSize,
          slots: slots,
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (named)
                for (var i = 0; i < slots.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs),
                  _SlotRow(slot: slots[i]),
                ]
              else ...[
                _LegendRow(stamped: true, label: 'Signed', count: ringSigned),
                const SizedBox(height: AppSpacing.xs),
                _LegendRow(stamped: false, label: 'Not signed', count: pending),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                caption ??
                    (r != null
                        ? '$ringTotal signer${ringTotal == 1 ? '' : 's'} on '
                              'this transaction · $present of $r required '
                              'signature${r == 1 ? '' : 's'} collected'
                        : '$ringTotal signer${ringTotal == 1 ? '' : 's'} on '
                              'this transaction · $present signature'
                              '${present == 1 ? '' : 's'} collected'),
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.stamped,
    required this.label,
    required this.count,
  });
  final bool stamped;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      children: [
        SealMark(stamped: stamped, size: AppSpacing.iconSmall),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$label ($count)',
          style: AppTypography.bodySmall.copyWith(color: s.ink),
        ),
      ],
    );
  }
}

/// One named signer in the legend: its seal, its name, and whether its
/// signature has arrived. The seal stamps itself when it does.
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot});

  final SignerSlot slot;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final dot = slot.color;
    return Row(
      children: [
        SealMark(stamped: slot.signed, size: AppSpacing.iconSmall),
        const SizedBox(width: AppSpacing.sm),
        if (dot != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            slot.label,
            style: AppTypography.bodySmall.copyWith(
              color: slot.signed ? s.ink : s.inkSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (slot.isLocal) ...[
          const SizedBox(width: AppSpacing.sm),
          const _QuietWord('This wallet'),
        ],
        if (slot.isHardware) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.usb_outlined,
            size: AppSpacing.iconSmall,
            color: s.inkFaint,
          ),
        ],
        const SizedBox(width: AppSpacing.sm),
        Text(
          slot.signed ? 'Signed' : 'Not signed',
          style: AppTypography.caption.copyWith(
            color: slot.signed ? s.inkSecondary : s.inkFaint,
          ),
        ),
      ],
    );
  }
}

/// The neutral segmented ring, for the cosigner ring next door: one arc per
/// key in [colors] (a user-chosen colour, toned, or the key hairline), no
/// fill sweep. [strokeFraction] sets the weight.
CustomPainter keyRingPainter({
  required List<Color> colors,
  double strokeFraction = 0.08,
}) => _KeyRingPainter(colors: colors, strokeFraction: strokeFraction);

class _KeyRingPainter extends CustomPainter {
  const _KeyRingPainter({required this.colors, required this.strokeFraction});

  final List<Color> colors;
  final double strokeFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final total = colors.length;
    if (total == 0) return;
    final stroke = size.shortestSide * strokeFraction;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );
    const start = -math.pi / 2;
    final slot = (2 * math.pi) / total;
    final gap = total == 1
        ? 0.0
        : math.min(
            stroke * _SegmentRingPainter._seamStrokes / (rect.width / 2),
            slot * _SegmentRingPainter._maxSeamFraction,
          );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = total == 1 ? StrokeCap.butt : StrokeCap.round;
    for (var i = 0; i < total; i++) {
      canvas.drawArc(
        rect,
        start + i * slot + gap / 2,
        slot - gap,
        false,
        paint..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(_KeyRingPainter old) {
    if (old.strokeFraction != strokeFraction) return true;
    if (old.colors.length != colors.length) return true;
    for (var i = 0; i < colors.length; i++) {
      if (old.colors[i] != colors[i]) return true;
    }
    return false;
  }
}
