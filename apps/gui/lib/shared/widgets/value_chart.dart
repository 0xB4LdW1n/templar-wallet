// Value chart — the balance over time, the Dashboard's one rich thing
// (design.md, "The moments").
//
// Pure presentation: it takes points in and renders them. No bridge, service
// or feature imports; every number it shows comes from [ValueChart.formatValue]
// or [ValueChart.formatAxis].
//
// One accent line, the soft area under it (the single gradient the app
// allows, because it encodes data), a muted grid, mono axis labels and a dot
// on "now". Nothing glows and nothing loops.
//
// Interpolation is monotone cubic (Fritsch–Carlson). This is a correctness
// guardrail, not a style choice: a plain Catmull-Rom spline overshoots between
// samples and would draw a balance the wallet never held.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One sample of a value series.
class ChartPoint {
  const ChartPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

/// Formats a y-axis tick. [step] is the distance between two ticks, so a
/// formatter can show exactly as many decimals as the ticks differ by.
typedef AxisFormatter = String Function(double value, double step);

/// Line-and-area chart with a cursor.
///
/// Pointer model: with a mouse the cursor follows the hover and clears on
/// exit. On a touch platform ([AppLayout.isMobilePlatform]) there is no hover,
/// so a tap pins the cursor where the finger landed, a horizontal drag moves
/// it, and it stays after the finger lifts until the same sample is tapped
/// again — a read-out that vanished the instant the finger left the screen
/// was unreadable, because the finger was covering it. The read-out is then
/// drawn on the far side of the chart from the hairline so the hand never
/// hides it.
class ValueChart extends StatefulWidget {
  const ValueChart({
    super.key,
    required this.points,
    required this.formatValue,
    this.height = 132,
    this.lineColor,
    this.emptyMessage,
    this.animationKey,
    this.gridLines = 0,
    this.markLatest = false,
    this.axes = false,
    this.formatAxis,
    this.showReadout = true,
    this.onCursor,
  });

  /// Ascending by time. May be empty.
  final List<ChartPoint> points;

  /// Formats a value for the cursor read-out (fiat or coin units). Exact:
  /// this is a balance.
  final String Function(double) formatValue;

  final double height;

  /// Defaults to the runtime accent.
  final Color? lineColor;

  /// Shown centred over a flat baseline when [points] is empty. Only the
  /// baseline is drawn when null.
  final String? emptyMessage;

  /// Identifies "a different chart" for the entry animation. When set, the
  /// line redraws only if this changes — so a refreshed series (new data for
  /// the same view) updates without re-animating. Null = redraw on any
  /// change of the [points] list.
  final Object? animationKey;

  /// Without [axes]: hairlines behind the line, evenly spaced across the
  /// drawing band. 0 = none. Ignored with [axes], which draws its own three.
  final int gridLines;

  /// Drop a dot on the newest sample as the line lands — "now".
  final bool markLatest;

  /// Three hairlines on round values with their labels at the right edge,
  /// and dates along the bottom.
  final bool axes;

  /// Formats a y tick. Only used with [axes]; defaults to [formatValue].
  /// An axis tick is not a balance, so this one may be compact (`€1.2k`).
  /// An empty string leaves the tick unlabelled (the privacy mask).
  final AxisFormatter? formatAxis;

  /// Draw the cursor's read-out inside the chart. Turn off when the host
  /// shows it elsewhere through [onCursor].
  final bool showReadout;

  /// The sample under the cursor, or null when the cursor leaves.
  final ValueChanged<ChartPoint?>? onCursor;

  @override
  State<ValueChart> createState() => _ValueChartState();
}

class _ValueChartState extends State<ValueChart>
    with SingleTickerProviderStateMixin {
  /// Upper bound on rendered samples — a 1-year daily series is well under it,
  /// a per-transaction series of a busy wallet is not.
  static const int _maxRendered = 180;

  /// Room above the top tick and beside the plot, on the 4 px grid.
  static const double _topPad = AppSpacing.sm;
  static const double _bottomPad = AppSpacing.sm;
  static const double _sidePad = AppSpacing.xs;

  /// The band under the plot that holds the date labels.
  static const double _xBand = AppSpacing.xl;

  /// Between the plot's right edge and the y labels.
  static const double _yGap = AppSpacing.sm;

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: AppMotion.grand,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _draw,
    curve: AppMotion.settle,
  );

  List<ChartPoint> _sampled = const [];
  int? _cursor;

  /// Touch only: the cursor was placed by a tap or drag and survives the
  /// finger lifting. Never set with a mouse, so desktop behaviour is untouched.
  bool _pinned = false;
  bool _started = false;

  /// Layout-derived geometry, cached from the last layout pass so pointer
  /// hit-testing maps to exactly the pixels on screen.
  _ChartGeometry? _geom;

  @override
  void initState() {
    super.initState();
    _sampled = _downsample(widget.points, _maxRendered);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _startDraw();
    }
  }

  @override
  void didUpdateWidget(ValueChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) {
      _sampled = _downsample(widget.points, _maxRendered);
      _geom = null;
      final had = _cursor;
      // A pinned touch read-out rides through the per-minute data refresh;
      // the sample index is only approximate across the new list, but the
      // next tap corrects it and a vanishing read-out is worse.
      if (!_pinned || (_cursor ?? 0) >= _sampled.length) _cursor = null;
      if (_cursor == null) _pinned = false;
      if (had != null && _cursor == null) _reportLater(null);
      // With an animationKey the caller decides what counts as a new chart, so
      // a periodic data refresh updates the line without drawing it again.
      final k = widget.animationKey;
      if (k == null || k != oldWidget.animationKey) _startDraw();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _startDraw() {
    // Duration.zero under reduced motion — forward() then lands on 1 at once.
    _draw.duration = AppMotion.of(context, AppMotion.grand);
    _draw.forward(from: 0);
  }

  // ── Cursor ──────────────────────────────────────────────────────────────────

  void _report(int? i) {
    final cb = widget.onCursor;
    if (cb == null) return;
    cb(i == null || i >= _sampled.length ? null : _sampled[i]);
  }

  /// For changes made during a build pass, where the host cannot rebuild.
  void _reportLater(int? i) {
    if (widget.onCursor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(i);
    });
  }

  void _setCursor(int? i, {bool pinned = false}) {
    if (i == _cursor && pinned == _pinned) return;
    setState(() {
      _cursor = i;
      _pinned = pinned;
    });
    _report(i);
  }

  void _moveCursor(Offset local) {
    final g = _geom;
    if (g == null || g.xs.isEmpty) return;
    _setCursor(g.nearestByX(local.dx));
  }

  void _clearCursor() => _setCursor(null);

  /// Touch: place (or move) the pinned cursor; tapping the sample that is
  /// already pinned releases it.
  void _tapCursor(Offset local) {
    final g = _geom;
    if (g == null || g.xs.isEmpty) return;
    final i = g.nearestByX(local.dx);
    if (_pinned && i == _cursor) {
      _clearCursor();
      return;
    }
    _setCursor(i, pinned: true);
  }

  void _dragCursor(Offset local) {
    final g = _geom;
    if (g == null || g.xs.isEmpty) return;
    _setCursor(g.nearestByX(local.dx), pinned: true);
  }

  // ── Down-sampling ───────────────────────────────────────────────────────────

  /// Keeps first and last, and picks the sample nearest each interior time
  /// bucket — preserving the shape of long ranges without drawing 5k points.
  static List<ChartPoint> _downsample(List<ChartPoint> pts, int max) {
    if (pts.length <= max) return pts;

    double ms(int i) => pts[i].time.millisecondsSinceEpoch.toDouble();
    final t0 = ms(0);
    final span = ms(pts.length - 1) - t0;

    final out = <ChartPoint>[pts.first];
    var last = 0;

    if (span <= 0) {
      // Degenerate time axis (all samples share a timestamp): stride by index.
      final stride = pts.length / (max - 1);
      for (var b = 1; b < max - 1; b++) {
        final i = math.min((b * stride).floor(), pts.length - 1);
        if (i != last) {
          out.add(pts[i]);
          last = i;
        }
      }
    } else {
      final buckets = max - 2;
      var scan = 0;
      for (var b = 1; b <= buckets; b++) {
        final target = t0 + span * b / (buckets + 1);
        while (scan + 1 < pts.length && ms(scan + 1) <= target) {
          scan++;
        }
        var best = scan;
        if (scan + 1 < pts.length &&
            (ms(scan + 1) - target).abs() < (target - ms(scan)).abs()) {
          best = scan + 1;
        }
        if (best != last) {
          out.add(pts[best]);
          last = best;
        }
      }
    }

    if (last != pts.length - 1) out.add(pts.last);
    return out;
  }

  // ── Ticks and labels ────────────────────────────────────────────────────────

  /// Three round values that bracket [min]..[max]: the lowest multiple of a
  /// 1-2-5 step under the data, then one and two steps above it. The grid
  /// lands on numbers a reader can use instead of on arbitrary fractions.
  static (List<double>, double) _niceTicks(double min, double max) {
    var lo = min;
    var hi = max;
    if (!(hi > lo)) {
      final pad = math.max(lo.abs() * 0.05, 1.0);
      lo -= pad;
      hi += pad;
    }
    final rough = (hi - lo) / 2;
    final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    for (var k = 0; k < 4; k++) {
      for (final f in const [1.0, 2.0, 5.0]) {
        final step = f * mag * math.pow(10, k);
        final base = (lo / step).floor() * step;
        if (base + 2 * step >= hi - step * 1e-9) {
          return ([base, base + step, base + 2 * step], step);
        }
      }
    }
    final step = (hi - lo) / 2;
    return ([lo, lo + step, hi], step);
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// The read-out's date: to the minute for a short span, to the day else.
  static String _formatStamp(DateTime dt, bool short) {
    final date = '${dt.day} ${_months[dt.month - 1]}';
    if (short) return '$date ${_two(dt.hour)}:${_two(dt.minute)}';
    return '$date ${dt.year}';
  }

  /// An x tick: a clock time inside two days, a day inside four months, a
  /// month beyond that.
  static String _formatTick(DateTime dt, Duration span) {
    if (span.inHours <= 48) return '${_two(dt.hour)}:${_two(dt.minute)}';
    if (span.inDays <= 120) return '${dt.day} ${_months[dt.month - 1]}';
    return '${_months[dt.month - 1]} ${dt.year}';
  }

  Duration get _span {
    if (_sampled.length < 2) return Duration.zero;
    return _sampled.last.time.difference(_sampled.first.time);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final line = widget.lineColor ?? s.accent;
    final area = widget.lineColor == null
        ? s.accentSoft
        : line.withValues(alpha: s.isDark ? 0.16 : 0.12);
    final mono = AppTypography.monoSmall.copyWith(color: s.inkFaint);

    if (_sampled.isEmpty) {
      // A flat baseline where the line would be, and the reason it is not.
      final message = widget.emptyMessage;
      return SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: widget.axes ? _xBand : 0,
              child: Container(height: 1, color: s.edge),
            ),
            if (message != null)
              Center(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(color: s.inkFaint),
                ),
              ),
          ],
        ),
      );
    }

    final cursor = _cursor;
    final active = cursor != null && cursor < _sampled.length;
    final touch = AppLayout.isMobilePlatform;
    final span = _span;

    return Semantics(
      label:
          'Value chart, ${_sampled.length} points, latest '
          '${widget.formatValue(_sampled.last.value)}',
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 0.0;
            final h = c.maxHeight.isFinite ? c.maxHeight : widget.height;
            if (w <= 0 || h <= 0) {
              _geom = null;
              return const SizedBox.shrink();
            }

            // Value range: round ticks with axes, the data's own extremes
            // without.
            var minV = double.infinity;
            var maxV = double.negativeInfinity;
            for (final p in _sampled) {
              final v = p.value.isFinite ? p.value : 0.0;
              if (v < minV) minV = v;
              if (v > maxV) maxV = v;
            }

            List<_Label> yLabels = const [];
            List<double> ticks = const [];
            double lo = minV;
            double hi = maxV;
            double right = w - _sidePad;
            double left = _sidePad;
            double bottom = h - _bottomPad;
            if (widget.axes) {
              final (t, step) = _niceTicks(minV, maxV);
              ticks = t;
              lo = t.first;
              hi = t.last;
              final fmt =
                  widget.formatAxis ??
                  (double v, double _) => widget.formatValue(v);
              yLabels = [for (final v in t) _Label.of(fmt(v, step), mono)];
              final labelW = yLabels.fold<double>(
                0,
                (m, l) => math.max(m, l.painter.width),
              );
              left = 0;
              right = math.max(0, w - (labelW > 0 ? labelW + _yGap : 0));
              bottom = math.max(_topPad, h - _xBand);
            }

            final geom = _ChartGeometry.build(
              _sampled,
              Rect.fromLTRB(left, _topPad, right, math.max(_topPad, bottom)),
              lo: lo,
              hi: hi,
            );
            _geom = geom;

            final xLabels = widget.axes
                ? _xTicks(geom, span, mono)
                : const <(double, _Label)>[];

            final paint = RepaintBoundary(
              child: AnimatedBuilder(
                animation: _progress,
                builder: (_, _) => CustomPaint(
                  size: Size(w, h),
                  painter: _ValueChartPainter(
                    geom: geom,
                    progress: _progress.value,
                    line: line,
                    area: area,
                    grid: s.edge,
                    gridLines: widget.axes ? 0 : widget.gridLines,
                    ticks: ticks,
                    yLabels: yLabels,
                    xLabels: xLabels,
                    markLatest: widget.markLatest,
                    hairline: s.edgeStrong,
                    ring: s.panel,
                    chipFill: s.panelInset,
                    chipEdge: s.edge,
                    cursor: active ? cursor : null,
                    cursorValue: active
                        ? widget.formatValue(_sampled[cursor].value)
                        : null,
                    cursorStamp: active
                        ? _formatStamp(
                            _sampled[cursor].time,
                            span.inHours <= 48,
                          )
                        : null,
                    showReadout: widget.showReadout,
                    valueStyle: AppTypography.numericSmall.copyWith(
                      color: s.ink,
                    ),
                    stampStyle: mono,
                    isDark: s.isDark,
                    farSideChip: touch,
                  ),
                ),
              ),
            );

            if (touch) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _tapCursor(d.localPosition),
                // Horizontal-only so the dashboard's vertical scroll still
                // wins; no long-press recognizer, which would hold the list
                // still while a finger rests on the chart. The cursor stays
                // where the drag ended.
                onHorizontalDragStart: (d) => _dragCursor(d.localPosition),
                onHorizontalDragUpdate: (d) => _dragCursor(d.localPosition),
                child: paint,
              );
            }
            return MouseRegion(
              onHover: (e) => _moveCursor(e.localPosition),
              onExit: (_) => _clearCursor(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Horizontal-only so the dashboard's vertical scroll still wins.
                onHorizontalDragStart: (d) => _moveCursor(d.localPosition),
                onHorizontalDragUpdate: (d) => _moveCursor(d.localPosition),
                onHorizontalDragEnd: (_) => _clearCursor(),
                onHorizontalDragCancel: _clearCursor,
                onLongPressStart: (d) => _moveCursor(d.localPosition),
                onLongPressMoveUpdate: (d) => _moveCursor(d.localPosition),
                onLongPressEnd: (_) => _clearCursor(),
                onLongPressCancel: _clearCursor,
                child: paint,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Dates along the bottom: five evenly spaced in time, fewer when five
  /// would touch. The first is left-aligned to the plot, the last
  /// right-aligned, so none hangs off the edge.
  List<(double, _Label)> _xTicks(
    _ChartGeometry g,
    Duration span,
    TextStyle st,
  ) {
    if (_sampled.length < 2 || span <= Duration.zero) return const [];
    final t0 = _sampled.first.time;
    final left = g.plot.left;
    final width = g.plot.width;
    for (var n = 5; n >= 2; n--) {
      final out = <(double, _Label)>[];
      for (var i = 0; i < n; i++) {
        final f = i / (n - 1);
        final t = t0.add(span * f);
        final label = _Label.of(_formatTick(t, span), st);
        final x = left + width * f;
        final lx = i == 0
            ? x
            : i == n - 1
            ? x - label.painter.width
            : x - label.painter.width / 2;
        out.add((lx, label));
      }
      var fits = true;
      for (var i = 1; i < out.length; i++) {
        final prevEnd = out[i - 1].$1 + out[i - 1].$2.painter.width;
        if (out[i].$1 - prevEnd < AppSpacing.lg) {
          fits = false;
          break;
        }
      }
      if (fits) return out;
    }
    return const [];
  }
}

/// A laid-out label for the painter.
class _Label {
  _Label._(this.text, this.painter);

  factory _Label.of(String text, TextStyle style) => _Label._(
    text,
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(),
  );

  final String text;
  final TextPainter painter;
}

// ── Geometry ──────────────────────────────────────────────────────────────────

/// Screen-space projection of a series. Built once per layout pass and shared
/// by the painter and by pointer hit-testing.
class _ChartGeometry {
  _ChartGeometry._(
    this.xs,
    this.ys,
    this.pathXs,
    this.pathYs,
    this.plot,
    this.lo,
    this.hi,
  );

  final List<double> xs;
  final List<double> ys;

  /// Strictly-x-increasing subset used for the spline (duplicate x positions
  /// would divide by zero in the slope limiter).
  final List<double> pathXs;
  final List<double> pathYs;

  /// The band the samples were projected into.
  final Rect plot;

  /// The values at the bottom and the top of [plot].
  final double lo;
  final double hi;

  factory _ChartGeometry.build(
    List<ChartPoint> pts,
    Rect plot, {
    required double lo,
    required double hi,
  }) {
    final n = pts.length;
    final range = hi - lo;

    final t0 = pts.first.time.millisecondsSinceEpoch.toDouble();
    final span = pts.last.time.millisecondsSinceEpoch.toDouble() - t0;

    final xs = List<double>.filled(n, 0);
    final ys = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final double fx;
      if (n == 1) {
        fx = 0.5;
      } else if (span > 0) {
        fx = ((pts[i].time.millisecondsSinceEpoch.toDouble() - t0) / span)
            .clamp(0.0, 1.0);
      } else {
        fx = i / (n - 1);
      }
      xs[i] = plot.left + fx * plot.width;
      final v = pts[i].value.isFinite ? pts[i].value : 0.0;
      // A flat series sits on the centre line instead of dividing by zero.
      final fy = range > 0 ? ((v - lo) / range).clamp(0.0, 1.0) : 0.5;
      ys[i] = plot.bottom - fy * plot.height;
    }

    final pathXs = <double>[];
    final pathYs = <double>[];
    for (var i = 0; i < n; i++) {
      if (pathXs.isEmpty || xs[i] > pathXs.last) {
        pathXs.add(xs[i]);
        pathYs.add(ys[i]);
      } else {
        pathYs[pathYs.length - 1] = ys[i];
      }
    }

    return _ChartGeometry._(xs, ys, pathXs, pathYs, plot, lo, hi);
  }

  double yOf(double v) {
    final range = hi - lo;
    if (range <= 0) return plot.center.dy;
    return plot.bottom - (v - lo) / range * plot.height;
  }

  int nearestByX(double x) {
    if (xs.length == 1) return 0;
    var lo = 0;
    var hi = xs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 && (x - xs[lo - 1]).abs() <= (xs[lo] - x).abs()) return lo - 1;
    return lo;
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _ValueChartPainter extends CustomPainter {
  _ValueChartPainter({
    required this.geom,
    required this.progress,
    required this.line,
    required this.area,
    required this.grid,
    required this.gridLines,
    required this.ticks,
    required this.yLabels,
    required this.xLabels,
    required this.markLatest,
    required this.hairline,
    required this.ring,
    required this.chipFill,
    required this.chipEdge,
    required this.cursor,
    required this.cursorValue,
    required this.cursorStamp,
    required this.showReadout,
    required this.valueStyle,
    required this.stampStyle,
    required this.isDark,
    this.farSideChip = false,
  });

  final _ChartGeometry geom;
  final double progress;
  final Color line;
  final Color area;
  final Color grid;

  /// See [ValueChart.gridLines]; 0 when [ticks] carries the grid.
  final int gridLines;
  final List<double> ticks;
  final List<_Label> yLabels;
  final List<(double, _Label)> xLabels;
  final bool markLatest;
  final Color hairline;

  /// The panel tone, as a ring that lifts a dot off the line.
  final Color ring;
  final Color chipFill;
  final Color chipEdge;
  final int? cursor;
  final String? cursorValue;
  final String? cursorStamp;
  final bool showReadout;
  final TextStyle valueStyle;
  final TextStyle stampStyle;
  final bool isDark;

  /// Touch: draw the read-out at the chart edge opposite the hairline instead
  /// of beside it, so the finger that placed the cursor is not covering it.
  final bool farSideChip;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || geom.xs.isEmpty) return;
    final plot = geom.plot;
    final hair = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Grid first, so the line and its area always sit over it.
    if (ticks.isNotEmpty) {
      for (var i = 0; i < ticks.length; i++) {
        final y = geom.yOf(ticks[i]).roundToDouble() + 0.5;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), hair);
        if (i < yLabels.length) {
          final p = yLabels[i].painter;
          if (p.width > 0) {
            final ly = (y - p.height / 2).clamp(0.0, size.height - p.height);
            p.paint(canvas, Offset(size.width - p.width, ly));
          }
        }
      }
    } else {
      for (var i = 1; i <= gridLines; i++) {
        final y = plot.bottom - plot.height * i / (gridLines + 1);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), hair);
      }
      canvas.drawLine(
        Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5),
        hair,
      );
    }
    for (final (x, label) in xLabels) {
      label.painter.paint(
        canvas,
        Offset(x, size.height - label.painter.height),
      );
    }

    if (geom.pathXs.length < 2) {
      // Single sample: a dot is the honest rendering — a line would imply a
      // history that isn't there.
      _drawDot(canvas, Offset(geom.xs.first, geom.ys.first), 1);
      _drawCursor(canvas, size);
      return;
    }

    final path = _monotonePath(geom.pathXs, geom.pathYs);
    final p = progress.clamp(0.0, 1.0);

    canvas.save();
    // The line draws itself left to right; the clip reaches a hair past the
    // plot so the round cap at "now" is never sliced.
    canvas.clipRect(
      Rect.fromLTRB(
        0,
        0,
        plot.left + (plot.width + AppSpacing.xs) * p,
        size.height,
      ),
    );

    final baseline = ticks.isNotEmpty ? geom.yOf(ticks.first) : size.height;
    final top = geom.pathYs.reduce(math.min);
    final fill = Path.from(path)
      ..lineTo(geom.pathXs.last, baseline)
      ..lineTo(geom.pathXs.first, baseline)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [area, area.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(0, top, size.width, baseline)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );
    canvas.restore();

    // "Now", landing as the line reaches it. Painted outside the clip, so it
    // is never half a circle.
    if (markLatest) {
      final t = ((p - 0.85) / 0.15).clamp(0.0, 1.0);
      if (t > 0) _drawDot(canvas, Offset(geom.xs.last, geom.ys.last), t);
    }

    _drawCursor(canvas, size);
  }

  /// Fritsch–Carlson monotone cubic through the samples, emitted as cubic
  /// Béziers. Guarantees every drawn y stays within the neighbouring samples'
  /// values — no phantom peaks or dips.
  Path _monotonePath(List<double> xs, List<double> ys) {
    final n = xs.length;
    final secant = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      secant[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]);
    }

    final m = List<double>.filled(n, 0);
    m[0] = secant[0];
    m[n - 1] = secant[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = (secant[i - 1] + secant[i]) / 2;
    }

    for (var i = 0; i < n - 1; i++) {
      if (secant[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      var a = m[i] / secant[i];
      var b = m[i + 1] / secant[i];
      if (a < 0) {
        m[i] = 0;
        a = 0;
      }
      if (b < 0) {
        m[i + 1] = 0;
        b = 0;
      }
      final norm = a * a + b * b;
      if (norm > 9) {
        final tau = 3 / math.sqrt(norm);
        m[i] = tau * a * secant[i];
        m[i + 1] = tau * b * secant[i];
      }
    }

    final path = Path()..moveTo(xs[0], ys[0]);
    for (var i = 0; i < n - 1; i++) {
      final h = (xs[i + 1] - xs[i]) / 3;
      path.cubicTo(
        xs[i] + h,
        ys[i] + m[i] * h,
        xs[i + 1] - h,
        ys[i + 1] - m[i + 1] * h,
        xs[i + 1],
        ys[i + 1],
      );
    }
    return path;
  }

  /// A 3 px dot in the line's colour inside a 2 px ring of the panel.
  void _drawDot(Canvas canvas, Offset at, double t) {
    canvas.drawCircle(at, 5 * t, Paint()..color = ring);
    canvas.drawCircle(at, 3 * t, Paint()..color = line);
  }

  void _drawCursor(Canvas canvas, Size size) {
    final i = cursor;
    final value = cursorValue;
    if (i == null || value == null || i >= geom.xs.length) return;

    final x = geom.xs[i].roundToDouble() + 0.5;
    final y = geom.ys[i];

    canvas.drawLine(
      Offset(x, geom.plot.top),
      Offset(x, geom.plot.bottom),
      Paint()
        ..color = hairline
        ..strokeWidth = 1,
    );
    _drawDot(canvas, Offset(geom.xs[i], y), 1);
    if (!showReadout) return;

    // One line, date then value: the date quiet, the value in ink.
    final tp = TextPainter(
      text: TextSpan(
        children: [
          if (cursorStamp != null)
            TextSpan(text: '${cursorStamp!}  ', style: stampStyle),
          TextSpan(text: value, style: valueStyle),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, size.width - AppSpacing.xl));

    const padH = AppSpacing.sm;
    const padV = AppSpacing.xs;
    final w = tp.width + padH * 2;
    final h = tp.height + padV * 2;

    double left;
    if (farSideChip) {
      // Opposite half of the chart from the hairline: clear of the finger.
      left = x < size.width / 2 ? size.width - w - 1 : 1.0;
    } else {
      // Flip to the left of the hairline when it would clip the right edge.
      left = x + AppSpacing.sm;
      if (left + w > size.width - 1) left = x - AppSpacing.sm - w;
    }
    left = math.min(math.max(left, 1.0), math.max(1.0, size.width - w - 1));
    final top = geom.plot.top;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(AppSpacing.radiusSm),
    );
    canvas.drawRRect(rect, Paint()..color = chipFill);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = chipEdge,
    );
    tp.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(_ValueChartPainter old) =>
      !identical(old.geom, geom) ||
      old.progress != progress ||
      old.gridLines != gridLines ||
      old.markLatest != markLatest ||
      old.grid != grid ||
      old.cursor != cursor ||
      old.cursorValue != cursorValue ||
      old.showReadout != showReadout ||
      old.farSideChip != farSideChip ||
      // Theme flips rebuild with new colours but identical data.
      old.line != line ||
      old.area != area ||
      old.ring != ring ||
      old.isDark != isDark;
}
