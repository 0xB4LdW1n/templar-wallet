// The live edge (design.md, "Motion"): the outline of a thing that is in
// motion right now, drawn over its own border.
//
// Three states, each tied to something true:
//   breathing — it is waiting on the network: a pending transaction's row
//               in Activity. The outline swells and fades, slowly.
//   working   — the app is doing something to it this moment: signing,
//               broadcasting, a coin on its way. A short stroke runs round
//               the outline.
//   done      — it landed: the outline draws itself closed, once, and
//               stays.
//
// Only what is live loops, and nothing here moves a layout: the edge is
// painted over the child, never around it. Under reduced motion each state
// is its still frame.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// What a [LiveEdge] is saying.
enum LiveEdgeMode {
  /// Nothing drawn.
  off,

  /// Waiting on the network: the whole outline breathes.
  breathing,

  /// Being worked on now: a stroke runs round a faint outline.
  working,

  /// Landed: the outline draws itself closed and stays.
  done,
}

class LiveEdge extends StatefulWidget {
  const LiveEdge({
    super.key,
    required this.child,
    required this.mode,
    required this.color,
    this.borderRadius = BorderRadius.zero,
    this.width = 1.5,
    this.inset = 0,
  });

  final Widget child;
  final LiveEdgeMode mode;

  /// The hue of the edge: a status colour — `warning` for a wait, `success`
  /// for a signature and a broadcast — or the secondary ink.
  final Color color;

  /// The corner of the thing outlined.
  final BorderRadius borderRadius;

  /// Stroke width.
  final double width;

  /// Draws the edge this far inside the child's bounds (a row inside a
  /// card keeps clear of the card's own hairline).
  final double inset;

  /// Test seam: looping edges never settle, so `pumpAndSettle` would wait
  /// on them forever. True draws every state as its still frame.
  @visibleForTesting
  static bool debugStill = false;

  /// One breath, out and back.
  static const Duration breath = Duration(milliseconds: 2600);

  /// One lap of the running stroke.
  static const Duration lap = Duration(milliseconds: 1500);

  /// The closing stroke of [LiveEdgeMode.done].
  static const Duration close = Duration(milliseconds: 620);

  @override
  State<LiveEdge> createState() => _LiveEdgeState();
}

class _LiveEdgeState extends State<LiveEdge> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this);
  late final AnimationController _close = AnimationController(
    vsync: this,
    duration: LiveEdge.close,
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = LiveEdge.debugStill || AppMotion.reduced(context);
    _sync(entering: true);
  }

  @override
  void didUpdateWidget(LiveEdge old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _sync(entering: true);
  }

  /// Starts or stops the controllers for the mode at hand.
  void _sync({required bool entering}) {
    final mode = widget.mode;
    final loops =
        mode == LiveEdgeMode.breathing || mode == LiveEdgeMode.working;
    if (_still || !loops) {
      _loop.stop();
    } else {
      final period = mode == LiveEdgeMode.breathing
          ? LiveEdge.breath
          : LiveEdge.lap;
      if (_loop.duration != period || !_loop.isAnimating) {
        _loop.duration = period;
        _loop.repeat();
      }
    }
    if (mode == LiveEdgeMode.done) {
      if (_still) {
        _close.value = 1;
      } else if (entering && _close.status != AnimationStatus.forward) {
        if (_close.value < 1) _close.forward(from: 0);
      }
    } else {
      _close.value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _close.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == LiveEdgeMode.off) return widget.child;
    return CustomPaint(
      foregroundPainter: _EdgePainter(
        mode: widget.mode,
        color: widget.color,
        radius: widget.borderRadius,
        width: widget.width,
        inset: widget.inset,
        still: _still,
        loop: _loop,
        close: _close,
      ),
      child: widget.child,
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.mode,
    required this.color,
    required this.radius,
    required this.width,
    required this.inset,
    required this.still,
    required this.loop,
    required this.close,
  }) : super(repaint: Listenable.merge([loop, close]));

  final LiveEdgeMode mode;
  final Color color;
  final BorderRadius radius;
  final double width;
  final double inset;
  final bool still;
  final Animation<double> loop;
  final Animation<double> close;

  /// How much of the outline the running stroke covers.
  static const double _strokeShare = 0.24;

  /// The running stroke is laid in pieces that fade toward its tail.
  static const int _pieces = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(inset + width / 2);
    if (rect.width <= 0 || rect.height <= 0) return;
    // The corner follows the nesting rule: inner = outer − the distance in.
    final d = inset + width / 2;
    Radius inner(Radius r) =>
        Radius.elliptical(math.max(0, r.x - d), math.max(0, r.y - d));
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: inner(radius.topLeft),
      topRight: inner(radius.topRight),
      bottomLeft: inner(radius.bottomLeft),
      bottomRight: inner(radius.bottomRight),
    );
    final path = Path()..addRRect(rrect);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    switch (mode) {
      case LiveEdgeMode.off:
        return;
      case LiveEdgeMode.breathing:
        // In and out on a cosine: no hard turn at either end.
        final k = still ? 0.8 : 0.5 - 0.5 * math.cos(2 * math.pi * loop.value);
        pen.color = color.withValues(alpha: 0.26 + 0.74 * k);
        canvas.drawPath(path, pen);
      case LiveEdgeMode.working:
        pen.color = color.withValues(alpha: 0.24);
        canvas.drawPath(path, pen);
        final metric = _metric(path);
        if (metric == null) return;
        final head = (still ? 0.3 : loop.value) * metric.length;
        final piece = metric.length * _strokeShare / _pieces;
        for (var i = 0; i < _pieces; i++) {
          // Piece 0 is the tail, the last one the head.
          final end = head - (_pieces - 1 - i) * piece;
          pen.color = color.withValues(alpha: (i + 1) / _pieces);
          _stroke(canvas, metric, end - piece, end, pen);
        }
      case LiveEdgeMode.done:
        final t = Curves.easeOutCubic.transform(close.value.clamp(0.0, 1.0));
        if (t >= 1) {
          pen.color = color;
          canvas.drawPath(path, pen);
          return;
        }
        pen.color = color.withValues(alpha: 0.24);
        canvas.drawPath(path, pen);
        final metric = _metric(path);
        if (metric == null) return;
        // Two strokes leave the top-left and meet on the far side.
        final half = metric.length / 2 * t;
        pen.color = color;
        _stroke(canvas, metric, 0, half, pen);
        _stroke(canvas, metric, metric.length - half, metric.length, pen);
    }
  }

  ui.PathMetric? _metric(Path path) {
    final metrics = path.computeMetrics().iterator;
    return metrics.moveNext() ? metrics.current : null;
  }

  /// Strokes [from]..[to] along the closed outline, wrapping at its seam.
  void _stroke(
    Canvas canvas,
    ui.PathMetric metric,
    double from,
    double to,
    Paint pen,
  ) {
    final length = metric.length;
    if (length <= 0 || to <= from) return;
    var a = from % length;
    if (a < 0) a += length;
    final span = math.min(to - from, length);
    final b = a + span;
    if (b <= length) {
      canvas.drawPath(metric.extractPath(a, b), pen);
    } else {
      canvas.drawPath(metric.extractPath(a, length), pen);
      canvas.drawPath(metric.extractPath(0, b - length), pen);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.mode != mode ||
      old.color != color ||
      old.radius != radius ||
      old.width != width ||
      old.inset != inset ||
      old.still != still;
}
