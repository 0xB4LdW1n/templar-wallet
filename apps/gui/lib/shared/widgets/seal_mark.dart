import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';

/// The seal (design.md, "The seal"): the Templar cross in a ring.
///
/// Stamped, it says *this key has signed*. Empty, it says *this signature is
/// still missing*. It appears wherever signatures are counted and nowhere
/// else — it is not a logo, a bullet, or a success icon.
class SealMark extends StatelessWidget {
  const SealMark({
    super.key,
    required this.stamped,
    this.size = 20,
    this.semanticLabel,
  });

  final bool stamped;

  /// Diameter. 16 inline with text, 20 in a row, 32–48 for the moment a
  /// transaction is signed.
  final double size;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _SealPainter(
        stamped: stamped,
        fill: s.accent,
        cross: stamped ? s.onAccent : s.inkFaint.withValues(alpha: 0.55),
        ring: s.edgeStrong,
      ),
    );
    return Semantics(
      label: semanticLabel ?? (stamped ? 'Signed' : 'Not signed yet'),
      // The stamp lands: a short press down onto the page, no bounce. Keyed
      // on the state so it plays when a signature arrives, not on every build.
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.standard),
        switchInCurve: AppMotion.settle,
        switchOutCurve: AppMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.2, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(stamped), child: mark),
      ),
    );
  }
}

/// A row of seals: [required] of them, the first [signed] stamped. For a
/// policy that needs more signatures than fit, callers print the count
/// instead ("7 of 11").
class SealTally extends StatelessWidget {
  const SealTally({
    super.key,
    required this.signed,
    required this.required,
    this.size = 20,
  });

  final int signed;
  final int required;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$signed of $required signatures',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < required; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            SealMark(stamped: i < signed, size: size),
          ],
        ],
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({
    required this.stamped,
    required this.fill,
    required this.cross,
    required this.ring,
  });

  final bool stamped;
  final Color fill;
  final Color cross;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    if (stamped) {
      canvas.drawCircle(c, r, Paint()..color = fill);
    } else {
      canvas.drawCircle(
        c,
        r - 0.5,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    canvas.drawPath(crossPattee(c, r * 0.62), Paint()..color = cross);
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.stamped != stamped ||
      old.fill != fill ||
      old.cross != cross ||
      old.ring != ring;
}

/// The Templar cross as a glyph: the bare mark, no ring, in the ink of the
/// row it sits on — the icon of Templar Protocol, drawn like any other icon
/// (design.md, "Icons"). The ring is what makes a seal; without it the cross
/// says "Templar", not "signed".
class CrossGlyph extends StatelessWidget {
  const CrossGlyph({super.key, this.size = AppSpacing.icon, this.color});

  /// The side of the icon box, as an [Icon]'s `size`.
  final double size;

  /// The ink; the ambient icon colour when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink =
        color ??
        IconTheme.of(context).color ??
        AppScheme.of(context).inkSecondary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _CrossGlyphPainter(ink)),
    );
  }
}

class _CrossGlyphPainter extends CustomPainter {
  const _CrossGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Material glyphs leave a twelfth of their box as margin; so does this.
    canvas.drawPath(
      crossPattee(size.center(Offset.zero), size.shortestSide / 2 * 0.86),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CrossGlyphPainter old) => old.color != color;
}

/// The cross pattée of the brand mark, drawn geometrically so it stays crisp
/// at 16 px: four arms that are narrow at the centre and flare to the rim,
/// with concave sides and a faintly convex end.
Path crossPattee(Offset center, double radius) {
  final waist = radius * 0.14; // half-width where the arms meet
  final flare = radius * 0.5; // half-width at the rim
  final path = Path();
  for (var i = 0; i < 4; i++) {
    final arm = Path()
      ..moveTo(-waist, -waist)
      ..quadraticBezierTo(-waist * 1.1, -radius * 0.6, -flare, -radius * 0.94)
      ..quadraticBezierTo(0, -radius * 1.04, flare, -radius * 0.94)
      ..quadraticBezierTo(waist * 1.1, -radius * 0.6, waist, -waist)
      ..close();
    final turn = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(i * math.pi / 2);
    path.addPath(arm, Offset.zero, matrix4: turn.storage);
  }
  path.addRect(
    Rect.fromCenter(center: center, width: waist * 2, height: waist * 2),
  );
  return path;
}
