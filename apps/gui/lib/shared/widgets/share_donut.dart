// Share donut — how one whole splits across a few named parts (the Liquid
// page's split of its assets, design.md "The moments").
//
// Pure presentation: every number it shows comes in already formatted, and
// every share is computed from the values the caller hands it. Only what can
// be valued is a part: an asset nobody gave us a price for has no slice and
// no legend row — the caller says how many there are in one quiet line
// ([ShareDonut.footnote]) — so nothing is ever drawn as a guess.
//
// Interaction: hovering (pointer) or tapping (touch, or a click to pin) a
// slice or its legend row selects it: the other slices drain, and the middle
// of the ring names the part, its amount and its share. With nothing selected
// the middle states the whole. The legend repeats every share as a figure,
// so the chart reads without colour.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One part of the whole.
@immutable
class ShareSlice {
  const ShareSlice({
    required this.id,
    required this.label,
    required this.amount,
    required this.color,
    required this.value,
  });

  /// Stable identity (an asset id): selection follows it across rebuilds.
  final String id;

  /// The part's name, in ink.
  final String label;

  /// The part's own amount, already formatted (`0.00500000 LBTC`). Shown in
  /// the middle of the ring while the part is selected.
  final String amount;

  /// The slice's hue.
  final Color color;

  /// The part's value in the common unit the shares are measured in.
  final double value;
}

/// A ring of [slices] with its legend, beside it ([legendBeside]) or under it.
class ShareDonut extends StatefulWidget {
  const ShareDonut({
    super.key,
    required this.slices,
    required this.totalLabel,
    required this.totalValue,
    this.footnote,
    this.size = 160,
    this.thickness = 18,
    this.legendBeside = true,
    this.masked = false,
  });

  final List<ShareSlice> slices;

  /// The middle of the ring with nothing selected: a short label over the
  /// whole's figure (`Valued` / `€341.05`).
  final String totalLabel;
  final String totalValue;

  /// One quiet line under the legend for what the ring leaves out
  /// (`2 assets without a price`).
  final String? footnote;

  final double size;
  final double thickness;
  final bool legendBeside;

  /// Privacy mask on: amounts and figures arrive masked; the ring is drawn
  /// without shares (its proportions would give the amounts away).
  final bool masked;

  @override
  State<ShareDonut> createState() => _ShareDonutState();
}

class _ShareDonutState extends State<ShareDonut>
    with SingleTickerProviderStateMixin {
  /// Under the pointer (ring or legend). Wins over [_pinned] while present.
  String? _hovered;

  /// Chosen by a tap; a second tap on the same part clears it.
  String? _pinned;

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: AppMotion.grand,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppMotion.reduced(context)) {
        _draw.value = 1;
      } else {
        _draw.forward();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ShareDonut old) {
    super.didUpdateWidget(old);
    final ids = {for (final s in widget.slices) s.id};
    if (_pinned != null && !ids.contains(_pinned)) _pinned = null;
    if (_hovered != null && !ids.contains(_hovered)) _hovered = null;
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  String? get _selected => _hovered ?? _pinned;

  double get _total => widget.slices.fold<double>(0, (sum, s) => sum + s.value);

  /// The share of [s] in percent, or null when the whole is nothing.
  double? _share(ShareSlice s) {
    final total = _total;
    if (total <= 0) return null;
    return s.value / total * 100;
  }

  static String _percent(double p) {
    if (p >= 99.95) return '100%';
    if (p > 0 && p < 0.1) return '<0.1%';
    return '${p.toStringAsFixed(p >= 10 ? 0 : 1)}%';
  }

  void _toggle(String id) =>
      setState(() => _pinned = _pinned == id ? null : id);

  /// The slice under [local] (ring-box coordinates), or null.
  String? _hit(Offset local) {
    final r = widget.size / 2;
    final d = local - Offset(r, r);
    final dist = d.distance;
    // A band a little wider than the ring: a thin mark, a generous target.
    final outer = r + AppSpacing.xs;
    final inner = r - widget.thickness - AppSpacing.sm;
    if (dist > outer || dist < inner) return null;
    // Angle clockwise from twelve o'clock, 0..2π.
    var a = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (a < 0) a += 2 * math.pi;
    final total = _total;
    if (total <= 0) return null;
    var start = 0.0;
    for (final s in widget.slices) {
      final sweep = s.value / total * 2 * math.pi;
      if (a >= start && a < start + sweep) return s.id;
      start += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final selected = widget.slices.where((x) => x.id == _selected).firstOrNull;
    final slices = widget.slices;

    final ring = SizedBox.square(
      dimension: widget.size,
      child: MouseRegion(
        onHover: (e) {
          final id = _hit(e.localPosition);
          if (id != _hovered) setState(() => _hovered = id);
        },
        onExit: (_) {
          if (_hovered != null) setState(() => _hovered = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) {
            final id = _hit(e.localPosition);
            if (id != null) {
              _toggle(id);
            } else if (_pinned != null) {
              setState(() => _pinned = null);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) => CustomPaint(
                    painter: _RingPainter(
                      values: [
                        for (final x in slices) widget.masked ? 1 : x.value,
                      ],
                      colors: [
                        for (final x in slices)
                          widget.masked ? s.edgeStrong : x.color,
                      ],
                      selectedIndex: widget.masked
                          ? null
                          : slices.indexWhere((x) => x.id == _selected) < 0
                          ? null
                          : slices.indexWhere((x) => x.id == _selected),
                      thickness: widget.thickness,
                      track: s.edge,
                      progress: AppMotion.settle.transform(_draw.value),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(widget.thickness + AppSpacing.md),
                child: _Middle(
                  selected: selected,
                  share: selected == null || widget.masked
                      ? null
                      : _share(selected),
                  totalLabel: widget.totalLabel,
                  totalValue: widget.totalValue,
                  percent: _percent,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final note = widget.footnote;
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final x in widget.slices)
          _LegendRow(
            slice: x,
            share: widget.masked ? null : _share(x),
            percent: _percent,
            selected: x.id == _selected,
            dimmed: _selected != null && x.id != _selected,
            onHover: (inside) => setState(
              () => _hovered = inside
                  ? x.id
                  : (_hovered == x.id ? null : _hovered),
            ),
            onTap: () => _toggle(x.id),
          ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              0,
            ),
            child: Text(
              note,
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
          ),
      ],
    );

    final semantics = Semantics(
      container: true,
      label: _semanticSummary(),
      child: widget.legendBeside
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ring,
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: legend),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: ring),
                const SizedBox(height: AppSpacing.lg),
                legend,
              ],
            ),
    );
    return semantics;
  }

  String _semanticSummary() {
    if (widget.masked) return 'Split of assets, hidden';
    final parts = [
      for (final x in widget.slices) '${x.label} ${_percent(_share(x) ?? 0)}',
      ?widget.footnote,
    ];
    return 'Split of assets: ${parts.join(', ')}';
  }
}

/// The middle of the ring: the selected part, or the whole.
class _Middle extends StatelessWidget {
  const _Middle({
    required this.selected,
    required this.share,
    required this.totalLabel,
    required this.totalValue,
    required this.percent,
  });

  final ShareSlice? selected;
  final double? share;
  final String totalLabel;
  final String totalValue;
  final String Function(double) percent;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final sel = selected;
    final String top;
    final String figure;
    final String? foot;
    if (sel == null) {
      top = totalLabel;
      figure = totalValue;
      foot = null;
    } else {
      top = sel.label;
      figure = share == null ? '' : percent(share!);
      foot = sel.amount;
    }
    Widget line(String text, TextStyle style) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, textAlign: TextAlign.center, style: style),
    );
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.instant),
      child: Column(
        key: ValueKey(sel?.id ?? '_whole'),
        mainAxisSize: MainAxisSize.min,
        children: [
          line(top, AppTypography.caption.copyWith(color: s.inkSecondary)),
          if (figure.isNotEmpty)
            line(
              figure,
              AppTypography.numericLargeOf(context).copyWith(color: s.ink),
            ),
          if (foot != null && foot.isNotEmpty)
            line(foot, AppTypography.numericSmall.copyWith(color: s.inkFaint)),
        ],
      ),
    );
  }
}

/// One legend row: swatch, name, share — one line. 32 tall on desktop, the
/// touch floor on a phone. Selected is a surface step, like any selection.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.share,
    required this.percent,
    required this.selected,
    required this.dimmed,
    required this.onHover,
    required this.onTap,
  });

  final ShareSlice slice;

  /// Null under the privacy mask: the share would give the amount away.
  final double? share;
  final String Function(double) percent;
  final bool selected;
  final bool dimmed;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    const swatch = AppSpacing.sm;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.instant),
            curve: AppMotion.settle,
            constraints: BoxConstraints(
              minHeight: phone ? AppLayout.minTouchTarget : AppSpacing.xxl,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: selected ? s.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: AnimatedOpacity(
              duration: AppMotion.of(context, AppMotion.instant),
              opacity: dimmed ? 0.55 : 1,
              child: Row(
                children: [
                  Container(
                    width: swatch,
                    height: swatch,
                    decoration: BoxDecoration(
                      color: slice.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      slice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(color: s.ink),
                    ),
                  ),
                  if (share != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      percent(share!),
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: AppTypography.numeric.copyWith(color: s.ink),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.values,
    required this.colors,
    required this.selectedIndex,
    required this.thickness,
    required this.track,
    required this.progress,
  });

  final List<double> values;
  final List<Color> colors;
  final int? selectedIndex;
  final double thickness;
  final Color track;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Room for the selected slice to grow by a nudge without clipping.
    final radius = size.shortestSide / 2 - thickness / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      // Nothing to split: the empty track, so the ring's place still reads.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..color = track,
      );
      return;
    }
    if (progress <= 0) return;

    // A 2 px surface gap between neighbours, as an angle at this radius.
    final gap = values.length > 1 ? 2 / radius : 0.0;
    var start = -math.pi / 2;
    final full = 2 * math.pi * progress;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * full;
      final drawn = math.max(0.0, sweep - gap);
      if (drawn > 0) {
        final isSel = selectedIndex == i;
        final dim = selectedIndex != null && !isSel;
        canvas.drawArc(
          rect,
          start + gap / 2,
          drawn,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSel ? thickness + AppSpacing.xs : thickness
            ..strokeCap = StrokeCap.butt
            ..color = dim ? colors[i].withValues(alpha: 0.3) : colors[i],
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.selectedIndex != selectedIndex ||
      old.track != track ||
      old.thickness != thickness ||
      !_listEq(old.values, values) ||
      !_listEq(old.colors, colors);

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
